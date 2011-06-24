#!/usr/bin/perl
use test::helper qw($_real $_point);
use Test::More;
eval {
   require 'sys/syscall.ph'; # for SYS_statfs
} or plan skip_all => 'No syscall.ph';

# Maybe not the best way to do this... but it works. Only extract the values
# we care about, so we don't have to worry about changing field ordering
# around and other such nastiness.
my $packmask;
if ($^O eq 'linux') {
    $packmask = 'x[L!]L![6]x[L!]L!';
}
elsif ($^O eq 'freebsd') {
	# Only sure about this on 64-bit FreeBSD...
	$packmask = 'x[16]Qx[8]Q[2]qQqx[112]Lx[4]';
}
elsif ($^O eq 'netbsd') {
	# Only sure about this on 64-bit NetBSD...
	$packmask = 'x[8]Lx![q]x[16]Q[3]x[8]Q[2]x[64]L';
}
elsif ($^O eq 'darwin') {
    # Accurate for OS X 10.6; 10.5 and earlier may not actually correspond
	# to this, if my understanding of statfs(2) on OS X is fair.
    $packmask = 'x[L!]L!x[L!]L![5]';
} else {
	plan skip_all => 'Platform not known, need to know how to statfs';
}

if ($^O eq 'netbsd' || $^O eq 'darwin') {
    # Ignoring the f_namelen field; no such animal on OS X statfs(), and
	# NetBSD's statvfs1(2) syscall doesn't seem to handle f_namelen right
	# for PUFFS-based filesystems. Not our failure, and mostly irrelevant.
    plan tests => 6;
}
else {
    plan tests => 7;
}
# Just make the buffer large enough that we don't have to care...
my ($statfs_data) = "\0" x 4096;
my ($tmp) = $_point;
if ($^O eq 'netbsd') {
    # NetBSD doesn't have statfs(2); statvfs1(2) is its closest analogue.
	ok(!syscall(&SYS_statvfs1,$tmp,$statfs_data,1),'statvfs1');
}
else {
	ok(!syscall(&SYS_statfs,$tmp,$statfs_data),'statfs');
}
my @list = unpack($packmask,$statfs_data);
diag "statfs: ",join(', ', @list);
is(shift(@list),4096,'block size');
is(shift(@list),1000000,'blocks');
is(shift(@list),500000,'blocks free');
shift(@list);
is(shift(@list),1000000,'files');
is(shift(@list),500000,'files free');
unless ($^O eq 'netbsd' || $^O eq 'darwin') {
    is(shift(@list),255,'namelen');
}
