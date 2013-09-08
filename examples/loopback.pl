#!/usr/bin/perl -w
use strict;

use Carp ();
local $SIG{'__WARN__'} = \&Carp::cluck;

my $has_threads = 0;
eval {
    require threads;
    require threads::shared;
    1;
} and do {
    $has_threads = 1;
    threads->import();
    threads::shared->import();
};

my $has_Filesys__Statvfs = 0;
eval {
    require Filesys::Statvfs;
    1;
} and do {
    $has_Filesys__Statvfs = 1;
    Filesys::Statvfs->import();
};

my $use_lchown = 0;
eval {
    require Lchown;
	1;
} and do {
	$use_lchown = 1;
	Lchown->import();
};

my $has_mknod = 0;
eval {
        require Unix::Mknod;
        1;
} and do {
        $has_mknod = 1;
	Unix::Mknod->import();
};

use blib;
use Fuse;
use IO::File;
use POSIX qw(ENOTDIR ENOENT ENOSYS EEXIST EPERM O_RDONLY O_RDWR O_APPEND O_CREAT setsid);
use Fcntl qw(S_ISBLK S_ISCHR S_ISFIFO SEEK_SET S_ISREG S_ISFIFO S_IMODE S_ISCHR S_ISBLK S_ISSOCK);
use Getopt::Long;

my %extraopts = ( 'threaded' => 0, 'debug' => 0 );
my($use_real_statfs, $pidfile, $logfile);
GetOptions(
    'use-threads'       => sub {
        if ($has_threads) {
            $extraopts{'threaded'} = 1;
        }
    },
    'debug'             => sub {
        $extraopts{'debug'} = 1;
    },
    'use-real-statfs'   => \$use_real_statfs,
    'pidfile=s'         => \$pidfile,
    'logfile=s'         => \$logfile,
) || die('Error parsing options');

sub fixup { return "/tmp/fusetest-" . $ENV{LOGNAME} . shift }

sub x_getattr {
    my ($file) = fixup(shift);
    my (@list) = lstat($file);
    return -$! unless @list;
    return @list;
}

sub x_getdir {
    my ($dirname) = fixup(shift);
    unless(opendir(DIRHANDLE,$dirname)) {
        return -ENOENT();
    }
    my (@files) = readdir(DIRHANDLE);
    closedir(DIRHANDLE);
    return (@files, 0);
}

sub x_open {
    my ($file) = fixup(shift);
    my ($mode) = shift;
    return -$! unless sysopen(FILE,$file,$mode);
    close(FILE);
    return 0;
}

sub x_read {
    my ($file,$bufsize,$off) = @_;
    my ($rv) = -ENOSYS();
    my ($handle) = new IO::File;
    return -ENOENT() unless -e ($file = fixup($file));
    my ($fsize) = -s $file;
    return -ENOSYS() unless open($handle,$file);
    if(seek($handle,$off,SEEK_SET)) {
        read($handle,$rv,$bufsize);
    }
    return $rv;
}

sub x_read_buf {
    my ($file, $size, $off, $bufvec) = @_;
    my $rv = 0;
    my ($handle) = new IO::File;
    return -ENOENT() unless -e ($file = fixup($file));
    my ($fsize) = -s $file;
    return -ENOSYS() unless open($handle,$file);
    if(seek($handle,$off,SEEK_SET)) {
        $rv = $bufvec->[0]{'size'} = read($handle,$bufvec->[0]{'mem'},$size);
    }
    return $rv;
}

sub x_write {
    my ($file,$buf,$off) = @_;
    my ($rv);
    return -ENOENT() unless -e ($file = fixup($file));
    my ($fsize) = -s $file;
    return -ENOSYS() unless open(FILE,'+<',$file);
    if($rv = seek(FILE,$off,SEEK_SET)) {
        $rv = print(FILE $buf);
    }
    $rv = -ENOSYS() unless $rv;
    close(FILE);
    return length($buf);
}

sub x_write_buf {
    my ($file,$off,$bufvec) = @_;
    my ($rv);
    return -ENOENT() unless -e ($file = fixup($file));
    my ($fsize) = -s $file;
    return -ENOSYS() unless open(FILE,'+<',$file);
    # If by some chance we get a non-contiguous buffer, or an FD-based
    # buffer (or both!), then copy all of it into one contiguous buffer.
    if ($#$bufvec > 0 || $bufvec->[0]{flags} & &Fuse::FUSE_BUF_IS_FD()) {
        my $single = [ {
                flags   => 0,
                fd      => -1,
                mem     => undef,
                pos     => 0,
                size    => Fuse::fuse_buf_size($bufvec),
        } ];
        Fuse::fuse_buf_copy($single, $bufvec);
        $bufvec = $single;
    }
    if($rv = seek(FILE,$off,SEEK_SET)) {
        $rv = print(FILE $bufvec->[0]{mem});
    }
    $rv = -ENOSYS() unless $rv;
    close(FILE);
    return $rv;
}

sub err { return (-shift || -$!) }

sub x_readlink { return readlink(fixup(shift));         }
sub x_unlink   { return unlink(fixup(shift)) ? 0 : -$!; }

sub x_symlink { print "symlink\n"; return symlink(shift,fixup(shift)) ? 0 : -$!; }

sub x_rename {
    my ($old) = fixup(shift);
    my ($new) = fixup(shift);
    my ($err) = rename($old,$new) ? 0 : -ENOENT();
    return $err;
}
sub x_link { return link(fixup(shift),fixup(shift)) ? 0 : -$! }
sub x_chown {
    my ($fn) = fixup(shift);
    local $!;
    print "nonexistent $fn\n" unless -e $fn;
    my ($uid,$gid) = @_;
    if( $use_lchown ){
		lchown($uid, $gid, $fn);
	}else{
		chown($uid, $gid, $fn);
	}
    return -$!;
}
sub x_chmod {
    my ($fn) = fixup(shift);
    my ($mode) = shift;
    my ($err) = chmod($mode,$fn) ? 0 : -$!;
    return $err;
}
sub x_truncate { return truncate(fixup(shift),shift) ? 0 : -$! ; }
sub x_utime { return utime($_[1],$_[2],fixup($_[0])) ? 0:-$!; }

sub x_mkdir { my ($name, $perm) = @_; return 0 if mkdir(fixup($name),$perm); return -$!; }
sub x_rmdir { return 0 if rmdir fixup(shift); return -$!; }

sub x_mknod {
    # since this is called for ALL files, not just devices, I'll do some checks
    # and possibly run the real mknod command.
    my ($file, $modes, $dev) = @_;
    $file = fixup($file);
    undef $!;
    if (S_ISREG($modes)) {
        open(FILE, '>', $file) || return -$!;
        print FILE '';
        close(FILE);
        chmod S_IMODE($modes), $file;
        return 0;
    }
    elsif (S_ISFIFO($modes)) {
        my ($rv) = POSIX::mkfifo($file, S_IMODE($modes));
        return $rv ? 0 : -POSIX::errno();
    }
    elsif (S_ISCHR($modes) || S_ISBLK($modes)) {
        if($has_mknod){
                Unix::Mknod::mknod($file, $modes, $dev);
                return -$!;
        }else{
                return -POSIX::errno();
        }
    }
    # S_ISSOCK maybe should be handled; however, for our test it should
    # not really matter.
    else {
        return -&ENOSYS;
    }
    return -$!;
}

# kludge
sub x_statfs {
    if ($has_Filesys__Statvfs && $use_real_statfs) {
        (my($bsize, $frsize, $blocks, $bfree, $bavail,
            $files, $ffree, $favail, $flag,
            $namemax) = statvfs('/tmp')) || return -$!;
        return ($namemax, $files, $ffree, $blocks, $bavail, $bsize);
    }
    return 255,1000000,500000,1000000,500000,4096;
}

# Required for some edge cases where a simple fork() won't do.
# from http://perldoc.perl.org/perlipc.html#Complete-Dissociation-of-Child    -from-Parent
sub daemonize {
    chdir("/") || die "can't chdir to /: $!";
    open(STDIN, '<', '/dev/null') || die "can't read /dev/null: $!";
    if ($logfile) {
        open(STDOUT, '>', $logfile) || die "can't open logfile: $!";
    }
    else {
        open(STDOUT, '>', '/dev/null') || die "can't write to /dev/null: $!";
    }
    defined(my $pid = fork()) || die "can't fork: $!";
    exit if $pid; # non-zero now means I am the parent
    (setsid() != -1) || die "Can't start a new session: $!";
    open(STDERR, '>&', \*STDOUT) || die "can't dup stdout: $!";
    if ($pidfile) {
        open(PIDFILE, '>', $pidfile);
        print PIDFILE $$, "\n";
        close(PIDFILE);
    }
}

my ($mountpoint) = '';
if (@ARGV){
        $mountpoint = shift(@ARGV)
}
else {
        print <<'_EOT_';

 Usage: loopback.pl <mountpoint> [options]

 Options:
 --debug                Turn on debugging (verbose) output
 --use-threads          Use threads
 --use-real-statfs      Use real stat command against /tmp or generic values
 --pidfile              Create a file at the provided path containing PID
 --logfile              Direct stdout/stderr to file instead of /dev/null

_EOT_
	exit;
}

if (! -d $mountpoint) {
    print STDERR "ERROR: attempted to mount to non-directory\n";
    return -&ENOTDIR
}

daemonize();

Fuse::main(
    'mountpoint'    => $mountpoint,
    'getattr'       => 'main::x_getattr',
    'readlink'      => 'main::x_readlink',
    'getdir'        => 'main::x_getdir',
    'mknod'         => 'main::x_mknod',
    'mkdir'         => 'main::x_mkdir',
    'unlink'        => 'main::x_unlink',
    'rmdir'         => 'main::x_rmdir',
    'symlink'       => 'main::x_symlink',
    'rename'        => 'main::x_rename',
    'link'          => 'main::x_link',
    'chmod'         => 'main::x_chmod',
    'chown'         => 'main::x_chown',
    'truncate'      => 'main::x_truncate',
    'utime'         => 'main::x_utime',
    'open'          => 'main::x_open',
    'read'          => 'main::x_read',
    'read_buf'      => 'main::x_read_buf',
    'write'         => 'main::x_write',
    'write_buf'     => 'main::x_write_buf',
    'statfs'        => 'main::x_statfs',
    %extraopts,
);

# vim: ts=4 ai et hls
