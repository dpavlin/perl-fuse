#!/usr/bin/env perl

use strict;
no strict qw(refs);

use Carp;
local $SIG{'__WARN__'} = \&Carp::cluck;

use Fcntl qw(:mode);
use Errno qw(:POSIX);
use POSIX;

use constant FIOC_NAME => 'fioc';
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

sub usage {
    print <<'_EOT_';
Usage: fioclient.pl FIOC_FILE COMMAND

COMMANDS
  s [SIZE]     : get size if SIZE is omitted, set size otherwise
  r SIZE [OFF] : read SIZE bytes @ OFF (default 0) and output to stdout
  w SIZE [OFF] : write SIZE bytes @ OFF (default 0) from stdin

_EOT_
    exit(1);
}


usage() if scalar(@ARGV) < 2;

open(my $file, '+<', $ARGV[0]) or usage();

if ($ARGV[1] eq 's') {
    if (!defined $ARGV[2]) {
        my $size;
        my $rv = ioctl($file, FIOC_GET_SIZE, $size);
        if (ioctl($file, FIOC_GET_SIZE, $size) != 0) {
            croak($!);
        }
        printf("\%u\n", unpack('L', $size));
    }
    else {
        if (ioctl($file, FIOC_SET_SIZE, pack('L', $ARGV[2])) != 0) {
            croak($!);
        }
    }
}
elsif ($ARGV[1] eq 'r' || $ARGV[1] eq 'w') {
    usage() unless defined $ARGV[2];
    my $size = $ARGV[2];
    my $off = 0;
    if (defined $ARGV[3]) {
        $off = $ARGV[3];
    }
    seek($file, SEEK_SET, $off);
    if ($ARGV[1] eq 'r') {
        read($file, my $data, $size);
        print $data;
    }
    else {
        read(STDIN, my $data, $size);
        print $file $data;
    }
}
else {
    usage();
}

close($file);
