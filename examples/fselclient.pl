#!/usr/bin/env perl

use strict;
no strict qw(refs);

use Carp;
local $SIG{'__WARN__'} = \&Carp::cluck;

use IO::Poll qw(POLLIN);
use Fcntl;
use constant FSEL_FILES => 16;

my @fds;

foreach my $i (0 .. (FSEL_FILES - 1)) {
    sysopen($fds[$i], $ARGV[0] . '/' . sprintf('%X', $i), O_RDONLY)
        or croak($!);
}

my $poll = new IO::Poll;
foreach my $fd (@fds) {
    $poll->mask($fd, POLLIN);
}
while (1) {
    my $rc = $poll->poll();

    croak($!) if $rc < 0;

    foreach my $i (0 .. (FSEL_FILES - 1)) {
        if (!$poll->events($fds[$i])) {
            print '_:   ';
            next;
        }
        printf('%X:', $i);
        $rc = sysread($fds[$i], my $buf, 4096);
        croak($!) if !defined($rc);

        printf('%02d ', $rc);
    }
    print "\n";
}
