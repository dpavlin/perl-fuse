#!/usr/bin/env perl

# fioclient.pl: A Perl version of the fioclient IOCTL client example from
# the FUSE distribution.

use strict;
no strict qw(refs);

use Carp;
local $SIG{'__WARN__'} = \&Carp::cluck;

use Fcntl qw(:mode);
use Errno qw(:POSIX);
use POSIX;

if ($^O eq 'linux') {
    require 'linux/ioctl.ph';
}
else {
    require 'sys/ioccom.ph';
}

our %sizeof = ('size_t' => length(pack('L!')));
sub FIOC_GET_SIZE { _IOR(ord 'E', 0, 'size_t'); }
sub FIOC_SET_SIZE { _IOW(ord 'E', 1, 'size_t'); }

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
        if (!defined($rv) || $rv != 0) {
            croak($!);
        }
        printf("\%u\n", unpack('L!', $size));
    }
    else {
        my $rv = ioctl($file, FIOC_SET_SIZE, pack('L!', $ARGV[2]));
        if (!defined($rv) || $rv != 0) {
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
