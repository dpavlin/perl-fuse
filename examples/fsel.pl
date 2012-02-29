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
use Getopt::Long;

# $fsel_open_mask is used to limit the number of opens to 1 per file. This
# uses the file index (0-F) as $fh, as poll support requires a unique handle
# per open file. Lifting this would require more complete open file
# management.
my $fsel_open_mask :shared = 0;

# Maximum "file" size.
use constant FSEL_CNT_MAX   => 10;
use constant FSEL_FILES     => 16;

# Used only as a lock for $fsel_poll_notify_mask and @fsel_cnt.
my $fsel_mutex :shared;
# Mask indicating what FDs have poll notifications waiting.
my $fsel_poll_notify_mask :shared = 0;
# Poll notification handles.
my @fsel_poll_handle :shared;
# Number of bytes for each "file".
my @fsel_cnt :shared;
# Initialize all byte counts.
map { $fsel_cnt[$_] = 0 } (0 .. (FSEL_FILES - 1));

sub fsel_path_index {
    my ($path) = @_;
    print 'called ', (caller(0))[3], "\n";

    return -1 if $path !~ m{^/([0-9A-F])$};
    return hex($1);
}

sub fsel_getattr {
    my ($path) = @_;
    print 'called ', (caller(0))[3], "\n";
    my @stbuf = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);

    if ($path eq '/') {
        @stbuf[2, 3] = (S_IFDIR | 0555, 2);
        return @stbuf;
    }

    my $idx = fsel_path_index($path);
    return -&ENOENT if $idx < 0;

    @stbuf[2, 3, 7] = (S_IFREG | 0444, 1, $fsel_cnt[$idx]);
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
    return -&EACCES if $flags & O_ACCMODE != O_RDONLY;
    return -&EBUSY  if $fsel_open_mask & (1 << $idx);
    $fsel_open_mask |= (1 << $idx);

    # fsel files are nonseekable somewhat pipe-like files which get filled
    # up periodically by the producer thread, and consumed on read. Tell
    # FUSE to do this right.
    @{$info}{'direct_io', 'nonseekable'} = (1, 1);
    return (0, $idx);
}

sub fsel_release {
    my ($path, $flags, $fh) = @_;
    print 'called ', (caller(0))[3], "\n";

    $fsel_open_mask &= ~(1 << $fh);
    return 0;
}

sub fsel_read {
    my ($path, $size, $offset, $fh) = @_;
    print 'called ', (caller(0))[3], "\n";
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
    print 'called ', (caller(0))[3], ", path = \"$path\", fh = $fh, revents = $revents\n";

    lock($fsel_mutex);

    if ($ph) {
        my $oldph = $fsel_poll_handle[$fh];
        pollhandle_destroy($oldph) if $oldph;
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
    print 'called ', (caller(0))[3], "\n";
    local $SIG{'KILL'} = sub { threads->exit(); };
    my ($tv, $idx, $nr) = (0.25, 0, 1);

    while (1) {
        {
            my ($i, $t);
            lock($fsel_mutex);

            # This is the main producer loop which is executed every 250
            # msec. On each iteration, it adds one byte to 1, 2 or 4 files
            # and sends a poll notification if a poll handle is present.
            for (($i, $t) = (0, $idx); $i < $nr; $i++,
                    $t = (($t + int(FSEL_FILES / $nr)) % FSEL_FILES)) {
                next if $fsel_cnt[$t] == FSEL_CNT_MAX;

                $fsel_cnt[$t]++;
                if ($fsel_poll_notify_mask & (1 << $t)) {
                    printf("NOTIFY \%X\n", $t);
                    my $ph = $fsel_poll_handle[$t];
                    notify_poll($ph);
                    pollhandle_destroy($ph);
                    $fsel_poll_notify_mask &= ~(1 << $t);
                    $fsel_poll_handle[$t] = undef;
                }
            }

            $idx = ($idx + 1) % FSEL_FILES;
            if ($idx == 0) {
                # Cycle through 1, 2 and 4.
                $nr = ($nr * 2) % 7;
            }
        }

        sleep($tv);
    }
}

croak("Fuse doesn't have poll") unless Fuse::fuse_version() >= 2.8;

my %fuseargs = (
    'getattr'   => 'main::fsel_getattr',
    'readdir'   => 'main::fsel_readdir',
    'open'      => 'main::fsel_open',
    'release'   => 'main::fsel_release',
    'read'      => 'main::fsel_read',
    'poll'      => 'main::fsel_poll',
);

GetOptions(
    'use-threads'       => sub {
        print STDERR "Warning: Fuse currently has bugs related to threading which may cause misbehavior\n";
        $fuseargs{'threaded'} = 1;
    },
    'debug'             => sub {
        $fuseargs{'debug'} = 1;
    }
) || croak("Malformed options passed");

$fuseargs{'mountpoint'} = $ARGV[0];

my $thread = threads->create(\&fsel_producer);

Fuse::main(%fuseargs);

$thread->kill('KILL');
$thread->join();
