#!/usr/bin/perl
use test::helper qw($_real $_point);
use Test::More;
use Config;
use Filesys::Statvfs;

if ($^O eq 'netbsd' || $^O eq 'darwin') {
    # Ignoring the f_namelen field; no such animal on OS X statfs(), and
    # NetBSD's statvfs1(2) syscall doesn't seem to handle f_namelen right
    # for PUFFS-based filesystems. Not our failure, and mostly irrelevant.
    plan tests => 6;
}
else {
    plan tests => 7;
}
ok(my @list = (statvfs($_point))[1,2,3,5,6,9]);
diag "statfs: ",join(', ', @list);
is(shift(@list),4096,'block size');
is(shift(@list),1000000,'blocks');
is(shift(@list),500000,'blocks free');
is(shift(@list),1000000,'files');
is(shift(@list),500000,'files free');
unless ($^O eq 'netbsd' || $^O eq 'darwin') {
    is(shift(@list),255,'namelen');
}
