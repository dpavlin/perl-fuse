#!/usr/bin/perl -w
# filter_attr_t.pl
# Loopback fs that shows only files with a particular xattr

# (c) Reuben Thomas  29/11/2007-5/1/2008, based on example code from Fuse package

use strict;
#use blib;

use Fuse;
use File::ExtAttr ':all';
use IO::File;
use POSIX qw(ENOENT ENOSYS EEXIST EPERM O_RDONLY O_RDWR O_APPEND O_CREAT O_ACCMODE);
use Fcntl qw(S_ISBLK S_ISCHR S_ISFIFO SEEK_SET);

# Debug flag
my $debug = 0;

# Global settings
my ($tag, $real_root, $mountpoint);


sub debug {
	print STDERR shift if $debug ne 0;
}

my $can_syscall = eval {
	require 'syscall.ph'; # for SYS_mknod and SYS_lchown
};

if (!$can_syscall && open my $fh, '<', '/usr/include/sys/syscall.h') {
	my %sys = do { local $/ = undef;
			<$fh> =~ m/\#define \s+ (\w+) \s+ (\d+)/gxms;
		};
	close $fh;
	if ($sys{SYS_mknod} && $sys{SYS_lchown}) {
		*SYS_mknod  = sub { $sys{SYS_mknod}  };
		*SYS_lchown = sub { $sys{SYS_lchown} };
		$can_syscall = 1;
	}
}

sub tagged {
	my ($file) = @_;
	$file =~ s|/$||;
	my $ret = getfattr($file, $tag);
	debug("tagged: $file $tag " . defined($ret) . "\n");
	return $ret;
}

sub tag {
	return setfattr(shift, $tag, "");
}

sub detag {
	return delfattr(shift, $tag);
}

sub append_root {
	return $real_root . shift;
}

sub err {
	my ($err) = @_;
	return $err ? 0 : -$!;
}

sub x_getattr {
	debug("x_getattr ");
	my ($file) = append_root(shift);
	return -ENOENT() unless tagged($file);
	my (@list) = lstat($file);
	return -$! unless @list;
	return @list;
}

sub x_readlink {
	debug("x_readlink ");
	return readlink(append_root(shift));
}

sub x_getdir {
	debug("x_getdir ");
	my ($dirname) = append_root(shift);
	return -ENOENT() unless tagged($dirname) && opendir(DIRHANDLE, $dirname);
	my (@files) = readdir(DIRHANDLE);
	closedir(DIRHANDLE);
	my @psifiles = grep {tagged("$dirname/$_")} @files;
	return (@psifiles, 0);
}

sub x_mknod {
	my ($file, $modes, $dev) = @_;
	return -ENOSYS() if !$can_syscall;
	debug("x_mknod ");
	$file = append_root($file);
	return -EEXIST() if -e $file && !tagged($file);
	$! = 0;
	syscall(&SYS_mknod, $file, $modes, $dev);
	return -$! if $! != 0;
	return err(tag($file));
}

sub x_mkdir {
	debug("x_mkdir ");
	my ($name, $perm) = @_;
	$name = append_root($name);
	debug("$name");
	my $ret = err(mkdir $name, $perm);
	return $ret if $ret != 0;
	return err(tag($name));
}

sub x_open {
	my ($file) = append_root(shift);
	my ($mode) = shift;
	my $accmode = $mode & O_ACCMODE;
	debug("x_open $accmode " . O_ACCMODE . " " . O_WRONLY . " " . O_RDWR . " ");
	if ($accmode == O_WRONLY || $accmode == O_RDWR) {
		return -EEXIST() if -e $file && !tagged($file);
	} else {
		return -ENOENT() unless tagged($file);
	}
	return -$! unless sysopen(FILE, $file, $mode);
	close(FILE);
	return 0;
}

sub x_read {
	debug("x_read ");
	my ($file, $bufsize, $off) = @_;
	my ($rv) = -ENOSYS();
	my ($handle) = new IO::File;
	$file = append_root($file);
	return -ENOENT() unless tagged($file);
	my ($fsize) = -s $file;
	return -ENOSYS() unless open($handle, $file);
	if(seek($handle, $off, SEEK_SET)) {
		read($handle, $rv, $bufsize);
	}
	return $rv;
}

sub x_write {
	debug("x_write ");
	my ($file, $buf, $off) = @_;
	my ($rv);
	$file = append_root($file);
	return -ENOENT() unless tagged($file);
	my ($fsize) = -s $file;
	return -ENOSYS() unless open(FILE, '+<', $file);
	if ($rv = seek(FILE, $off, SEEK_SET)) {
		$rv = print(FILE $buf);
	}
	$rv = -ENOSYS() unless $rv;
	close(FILE);
	return length($buf);
}

sub x_unlink {
	debug("x_unlink ");
	my ($file) = append_root(shift);
	return -ENOENT() unless tagged($file);
	return err(detag($file));
}

sub x_symlink {
	debug("x_symlink ");
	my ($old) = shift;
	my ($new) = append_root(shift);
	return -EEXIST() if -e $new && !tagged($new);
	return err(symlink($old, $new));
}

sub x_rename {
	debug("x_rename ");
	my ($old) = append_root(shift);
	my ($new) = append_root(shift);
	return -ENOENT() unless tagged($old);
	return -EEXIST() unless !-e $new || tagged($new);
	my ($err) = rename($old, $new) ? 0 : -ENOENT();
	return $err;
}

sub x_link {
	debug("x_link ");
	my ($old) = append_root(shift);
	my ($new) = append_root(shift);
	return -ENOENT() unless tagged($old);
	return -EEXIST() unless !-e $new || tagged($new);
	return err(link($old, $new));
}

sub x_chown {
	return -ENOSYS() if !$can_syscall;
	debug("x_chown ");
	my ($fn) = append_root(shift);
	return -ENOENT() unless tagged($fn);
	my ($uid, $gid) = @_;
	# perl's chown() does not chown symlinks, it chowns the symlink's
	# target. It fails when the link's target doesn't exist, because
	# the stat64() syscall fails.
	# This causes error messages when unpacking symlinks in tarballs.
	my ($err) = syscall(&SYS_lchown, $fn, $uid, $gid, $fn) ? -$! : 0;
	return $err;
}

sub x_chmod {
	debug("x_chmod ");
	my ($fn) = append_root(shift);
	return -ENOENT() unless tagged($fn);
	my ($mode) = shift;
	return err(chmod($mode, $fn));
}

sub x_truncate {
	debug("x_truncate ");
	my ($fn) = append_root(shift);
	return -ENOENT() unless tagged($fn);
	return err(truncate($fn, shift));
}

sub x_utime {
	debug("x_utime ");
	my ($fn) = append_root($_[0]);
	return -ENOENT() unless tagged($fn);
	return err(utime($_[1], $_[2], $fn));
}

sub x_rmdir {
	debug("x_rmdir ");
	my $dir = append_root(shift);
	return -ENOENT() unless tagged($dir);
	return err(detag($dir));
}

sub x_statfs {
	debug("x_statfs\n");
	my $name = append_root(shift);
	my($bsize, $frsize, $blocks, $bfree, $bavail,
		$files, $ffree, $favail, $fsid, $basetype, $flag,
		$namemax, $fstr) = statvfs($real_root) || return -$!;
	return ($namemax, $files, $ffree, $blocks, $bavail, $bsize);
}

# If you run the script directly, it will run fusermount, which will in turn
# re-run this script.  Hence the funky semantics.

# Parse command-line arguments
$mountpoint = "";
if (@ARGV) {
	$tag = shift(@ARGV);
	$real_root = shift(@ARGV);
	$mountpoint = shift(@ARGV);
}

# Start up FUSE
Fuse::main(
	mountpoint=>$mountpoint,
#	debug   => 1,
	getattr =>"main::x_getattr",
	readlink=>"main::x_readlink",
	getdir  =>"main::x_getdir",
	mknod   =>"main::x_mknod",
	mkdir   =>"main::x_mkdir",
	unlink  =>"main::x_unlink",
	rmdir   =>"main::x_rmdir",
	symlink =>"main::x_symlink",
	rename  =>"main::x_rename",
	link    =>"main::x_link",
	chmod   =>"main::x_chmod",
	chown   =>"main::x_chown",
	truncate=>"main::x_truncate",
	utime   =>"main::x_utime",
	open    =>"main::x_open",
	read    =>"main::x_read",
	write   =>"main::x_write",
	statfs  =>"main::x_statfs",
);
