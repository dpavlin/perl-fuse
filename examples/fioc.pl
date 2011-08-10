#!/usr/bin/env perl

# fioc.pl: A Perl conversion of the fioc example IOCTL server program
# from the FUSE distribution. I've endeavored to stay pretty close
# structure-wise to the C version, while using Perl-specific features.
# I wrote this to provide a way to verify my ioctl() wrapper
# implementation would work properly. So far, it seems to, and it will
# interoperate with the C client as well.

use strict;
no strict qw(refs);

use threads;
use threads::shared;

use Carp;
local $SIG{'__WARN__'} = \&Carp::cluck;

use Fuse qw(:all);
use Fcntl qw(:mode);
use POSIX;

my $fioc_size :shared = 0;
use constant FIOC_NAME => 'fioc';
my $fioc_buf :shared = '';
use constant FIOC_NONE  => 0;
use constant FIOC_ROOT  => 1;
use constant FIOC_FILE  => 2;

require 'asm/ioctl.ph';

our %sizeof = ('size_t' => length(pack('L!')));
sub FIOC_GET_SIZE { _IOR(ord 'E', 0, 'size_t'); }
sub FIOC_SET_SIZE { _IOW(ord 'E', 1, 'size_t'); }
sub TCGETS { 0x5401; }

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

    return 0 if fioc_file_type($path) != FIOC_NONE;
    return -&ENOENT;
}

sub fioc_read {
    my ($path, $size, $offset) = @_;
    print 'called ', (caller(0))[3], "\n";

    return -&EINVAL if fioc_file_type($path) != FIOC_FILE;
    return q{} if $offset > $fioc_size;

    if ($size > $fioc_size - $offset) {
        $size - $fioc_size - $offset;
    }

    return substr($fioc_buf, $offset, $size);
}

sub fioc_write {
    my ($path, $data, $offset) = @_;
    print 'called ', (caller(0))[3], "\n";
    lock($fioc_buf);

    return -&EINVAL if fioc_file_type($path) != FIOC_FILE;
    return -&ENOMEM if fioc_expand($offset + length($data));

    substr($fioc_buf, $offset, length($data), $data);
    return length($data);
}

sub fioc_truncate {
    my ($path, $size) = @_;
    print 'called ', (caller(0))[3], "\n";
    lock($fioc_buf);

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

    return -&EINVAL if fioc_file_type($path) != FIOC_FILE;
    return -&ENOSYS if $flags & FUSE_IOCTL_COMPAT;

    if ($cmd == FIOC_GET_SIZE) {
        return(0, pack('L!', $fioc_size));
    }
    elsif ($cmd == FIOC_SET_SIZE) {
        lock($fioc_buf);
        fioc_resize(unpack('L!', $data));
        return 0;
    }
    elsif ($cmd == TCGETS) {
        # perl sends TCGETS as part of calling isatty() on opening a file;
        # this appears to be a more canonical answer
        return -&ENOTTY;
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
    'ioctl'     => 'main::fioc_ioctl',
    'threaded'  => 1);
