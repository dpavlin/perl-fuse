#!/usr/bin/env perl

use strict;
no strict qw(refs);

use Carp ();
local $SIG{'__WARN__'} = \&Carp::cluck;

use Fuse;
use Fcntl qw(:mode);
use Errno qw(:POSIX);
use POSIX;

my $fioc_size = 0;
use constant FIOC_NAME => 'fioc';
my $fioc_buf = '';
use constant FIOC_NONE  => 0;
use constant FIOC_ROOT  => 1;
use constant FIOC_FILE  => 2;

sub _IOC_NRBITS  { 8 }
sub _IOC_NRMASK  { ( 1 << &_IOC_NRBITS ) - 1 }
sub _IOC_NRSHIFT { 0 }

sub _IOC_TYPEBITS  { 8 }
sub _IOC_TYPEMASK  { ( 1 << &_IOC_TYPEBITS ) - 1 }
sub _IOC_TYPESHIFT { &_IOC_NRSHIFT + &_IOC_NRBITS }

sub _IOC_SIZEBITS { ( POSIX::uname() )[4] =~ /^i[3-6]86|x86_64$/ ? 14 : 13 }
sub _IOC_SIZEMASK  { ( 1 << &_IOC_SIZEBITS ) - 1 }
sub _IOC_SIZESHIFT { &_IOC_TYPESHIFT + &_IOC_TYPEBITS }

sub _IOC_DIRBITS  { 32 - &_IOC_NRBITS - &_IOC_TYPEBITS - &_IOC_SIZEBITS }
sub _IOC_DIRMASK  { ( 1 << &_IOC_DIRBITS ) - 1 }
sub _IOC_DIRSHIFT { &_IOC_SIZESHIFT + &_IOC_SIZEBITS }

sub _IOC_NONE  { ( POSIX::uname() )[4] =~ /^i[3-6]86|x86_64$/ ? 0 : 1 }
sub _IOC_WRITE { ( POSIX::uname() )[4] =~ /^i[3-6]86|x86_64$/ ? 1 : 4 }
sub _IOC_READ  { ( POSIX::uname() )[4] =~ /^i[3-6]86|x86_64$/ ? 2 : 2 }

sub _IOC ($$$$) {
  ( $_[0] << &_IOC_DIRSHIFT ) |  ( ord( $_[1] ) << &_IOC_TYPESHIFT ) |
    ( $_[2] << &_IOC_NRSHIFT ) | ( $_[3] << &_IOC_SIZESHIFT );
}

sub _IO ($$)    { &_IOC( &_IOC_NONE,               $_[0], $_[1], 0 ) }
sub _IOR ($$$)  { &_IOC( &_IOC_READ,               $_[0], $_[1], $_[2] ) }
sub _IOW ($$$)  { &_IOC( &_IOC_WRITE,              $_[0], $_[1], $_[2] ) }
sub _IOWR ($$$) { &_IOC( &_IOC_READ | &_IOC_WRITE, $_[0], $_[1], $_[2] ) }

sub FIOC_GET_SIZE { _IOR('E', 0, 4); }
sub FIOC_SET_SIZE { _IOW('E', 1, 4); }

sub fioc_resize {
    my ($size) = @_;
    print 'called ', (caller(0))[3], "\n";
    return 0 if $size == $fioc_size;
    
    if ($size < $fioc_size) {
        $fioc_buf = substr($fioc_buf, 0, $size);
    }
    else {
        $fioc_buf .= "\0" x ($size - $fioc_size);
    }
    $fioc_size = $size;
    return 0;
}

sub fioc_expand {
    my ($size) = @_;
    print 'called ', (caller(0))[3], "\n";
    if ($size > $fioc_size) {
        return fioc_resize($size);
    }
    return 0;
}

sub fioc_file_type {
    my ($path) = @_;
    print 'called ', (caller(0))[3], "\n";
    return FIOC_ROOT if $path eq '/';
    return FIOC_FILE if $path eq '/' . FIOC_NAME;
    return FIOC_NONE;
}

sub fioc_getattr {
    my ($path) = @_;
    print 'called ', (caller(0))[3], "\n";
    my @stbuf = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);

    $stbuf[4] = $<;
    $stbuf[5] = (split(/\s+/, $())[0];
    $stbuf[8] = $stbuf[9] = time();

    my $type = fioc_file_type($path);
    if ($type == FIOC_ROOT) {
        $stbuf[2] = S_IFDIR | 0755;
        $stbuf[3] = 2;
    }
    elsif ($type == FIOC_FILE) {
        $stbuf[2] = S_IFREG | 0644;
        $stbuf[3] = 1;
        $stbuf[7] = $fioc_size;
    }
    else {
        return -&ENOENT;
    }
    return @stbuf;
}

sub fioc_open {
    my ($path, $flags, $info) = @_;
    print 'called ', (caller(0))[3], "\n";

    if (fioc_file_type($path) != FIOC_NONE) {
        return 0;
    }
    return -&ENOENT;
}

sub fioc_read {
    my ($path, $size, $offset) = @_;
    print 'called ', (caller(0))[3], "\n";

    return -&EINVAL if fioc_file_type($path) != FIOC_FILE;

    if ($offset > $fioc_size) {
        return q{};
    }

    if ($size > $fioc_size - $offset) {
        $size - $fioc_size - $offset;
    }

    return substr($fioc_buf, $offset, $size);
}

sub fioc_write {
    my ($path, $data, $offset) = @_;
    print 'called ', (caller(0))[3], "\n";

    return -&EINVAL if fioc_file_type($path) != FIOC_FILE;

    if (fioc_expand($offset + length($data))) {
        return -&ENOMEM;
    }

    substr($fioc_buf, $offset, length($data), $data);
    return length($data);
}

sub fioc_truncate {
    my ($path, $size) = @_;
    print 'called ', (caller(0))[3], "\n";

    return -&EINVAL if fioc_file_type($path) != FIOC_FILE;

    return fioc_resize($size);
}

sub fioc_readdir {
    my ($path, $offset) = @_;
    print 'called ', (caller(0))[3], "\n";

    return -&EINVAL if fioc_file_type($path) != FIOC_ROOT;

    return ('.', '..', FIOC_NAME, 0);
}

sub fioc_ioctl {
    my ($path, $cmd, $flags, $data) = @_;
    print 'called ', (caller(0))[3], "\n";
    $cmd = unpack('L', pack('l', $cmd));

    print("fioc_ioctl(): path is \"$path\", cmd is $cmd, flags is $flags\n");
    return -&EINVAL if fioc_file_type($path) != FIOC_FILE;

    return -&ENOSYS if $flags & 0x1;

    if ($cmd == FIOC_GET_SIZE) {
        print "handling FIOC_GET_SIZE\n";
        return(0, pack('L', $fioc_size));
    }
    elsif ($cmd == FIOC_SET_SIZE) {
        print "handling FIOC_SET_SIZE\n";
        fioc_resize(unpack('L', $data));
        return 0;
    }

    return -&EINVAL;
}

croak("Fuse doesn't have ioctl") unless Fuse::fuse_version() >= 2.8;

Fuse::main(
    'mountpoint' => $ARGV[0],
    'getattr'   => 'main::fioc_getattr',
    'readdir'   => 'main::fioc_readdir',
    'truncate'  => 'main::fioc_truncate',
    'open'      => 'main::fioc_open',
    'read'      => 'main::fioc_read',
    'write'     => 'main::fioc_write',
    'ioctl'     => 'main::fioc_ioctl');
