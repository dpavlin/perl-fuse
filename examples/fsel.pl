#!/usr/bin/env perl

use strict;
no strict qw(refs);

use threads;
use threads::shared;

use Carp;
local $SIG{'__WARN__'} = \&Carp::cluck;

use Fuse qw(:all);
use Fcntl qw(:mode);
use POSIX;
use IO::Poll qw(POLLIN);
use Time::HiRes qw(sleep);
use Data::Dumper;

use constant FSEL_CNT_MAX   => 10;
use constant FSEL_FILES     => 16;

my $fsel_open_mask :shared = 0;
my $fsel_poll_notify_mask :shared = 0;
my @fsel_poll_handle :shared;
my @fsel_cnt :shared;
map { $fsel_cnt[$_] = 0 } (0 .. (FSEL_FILES - 1));

my $fsel_mutex :shared;

sub fsel_path_index {
    my ($path) = @_;
    print 'called ', (caller(0))[3], "\n";

    my $ch = substr($path, 1, 1);
    if (length($path) != 2 || substr($path, 0, 1) ne '/' || 
            $ch !~ /^[0-9A-F]$/) {
        return -1;
    }
    return hex($ch);
}

sub fsel_getattr {
    my ($path) = @_;
    print 'called ', (caller(0))[3], "\n";
    my @stbuf = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);

    if ($path eq '/') {
        $stbuf[2] = S_IFDIR | 0555;
        $stbuf[3] = 2;
        return @stbuf;
    }

    my $idx = fsel_path_index($path);
    return -&ENOENT if $idx < 0;

    $stbuf[2] = S_IFREG | 0444;
    $stbuf[3] = 1;
    $stbuf[7] = $fsel_cnt[$idx];
    return @stbuf;
}

sub fsel_readdir {
    my ($path, $offset) = @_;
    print 'called ', (caller(0))[3], "\n";

    return -&ENOENT if $path ne '/';

    return('.', '..', map { sprintf('%X', $_) } (0 .. (FSEL_FILES - 1)), 0);
}

sub fsel_open {
    my ($path, $flags, $info) = @_;
    print 'called ', (caller(0))[3], "\n";

    my $idx = fsel_path_index($path);
    return -&ENOENT if $idx < 0;
    return -&EACCES if $flags & 3 != O_RDONLY;
    return -&EBUSY if $fsel_open_mask & (1 << $idx);
    $fsel_open_mask |= (1 << $idx);

    $info->{'direct_io'} = 1;
    $info->{'nonseekable'} = 1;
    print "fsel_open(): ", $idx, "\n";
    my $foo = [ $idx + 0 ];
    return (0, $foo->[0]);
}

sub fsel_release {
    my ($path, $flags, $fh) = @_;
    print 'called ', (caller(0))[3], "\n";

    print "fsel_release(): \$fh is $fh\n";
    $fsel_open_mask &= ~(1 << $fh);
    printf("fsel_release(): \$fsel_open_mask is \%x\n", $fsel_open_mask);
    return 0;
}

sub fsel_read {
    my ($path, $size, $offset, $fh) = @_;
    print 'called ', (caller(0))[3], "\n";
    ## HACK
    #$fh = fsel_path_index($path);
    lock($fsel_mutex);

    if ($fsel_cnt[$fh] < $size) {
        $size = $fsel_cnt[$fh];
    }
    printf("READ   \%X transferred=\%u cnt=\%u\n", $fh, $size, $fsel_cnt[$fh]);
    $fsel_cnt[$fh] -= $size;

    return(chr($fh) x $size);
}

our $polled_zero :shared = 0;

sub fsel_poll {
    my ($path, $ph, $revents, $fh) = @_;
    print 'called ', (caller(0))[3], "\n";
    ## HACK
    #$fh = fsel_path_index($path);

    lock($fsel_mutex);

    if ($ph) {
        my $oldph = $fsel_poll_handle[$fh];
        if ($oldph) {
            pollhandle_destroy($oldph);
        }
        $fsel_poll_notify_mask |= (1 << $fh);
        $fsel_poll_handle[$fh] = $ph;
    }

    if ($fsel_cnt[$fh]) {
        $revents |= POLLIN;
        printf("POLL   \%X cnt=\%u polled_zero=\%u\n", $fh, $fsel_cnt[$fh],
                $polled_zero);
        $polled_zero = 0;
    }
    else {
        $polled_zero++;
    }

    return(0, $revents);
}

sub fsel_producer {
    local $SIG{'KILL'} = sub { threads->exit(); };
    print 'called ', (caller(0))[3], "\n";
    my $tv = 0.25;
    my $idx = 0;
    my $nr = 1;

    while (1) {
        {
            my ($i, $t);
            lock($fsel_mutex);

            for (($i, $t) = (0, $idx); $i < $nr; $i++,
                    $t = (($t + int(FSEL_FILES / $nr)) % FSEL_FILES)) {
                next if $fsel_cnt[$t] == FSEL_CNT_MAX;

                $fsel_cnt[$t]++;
                if ($fsel_poll_notify_mask & (1 << $t)) {
                    printf("NOTIFY \%X\n", $t);
                    my $ph = $fsel_poll_handle[$t];
                    notify_poll($ph);
                    pollhandle_destroy($ph);
                    $fsel_poll_handle[$t] = undef;
                    $fsel_poll_notify_mask &= ~(1 << $t);
                }
            }

            $idx = ($idx + 1) % FSEL_FILES;
            if ($idx == 0) {
                $nr = ($nr * 2) % 7;
            }
        }

        sleep($tv);
    }
}

croak("Fuse doesn't have poll") unless Fuse::fuse_version() >= 2.8;

my $thread = threads->create(\&fsel_producer);

Fuse::main(
    'mountpoint' => $ARGV[0],
    'getattr'   => 'main::fsel_getattr',
    'readdir'   => 'main::fsel_readdir',
    'open'      => 'main::fsel_open',
    'release'   => 'main::fsel_release',
    'read'      => 'main::fsel_read',
    'poll'      => 'main::fsel_poll',
    'threaded'  => 1,
);

$thread->kill('KILL');
$thread->join();
