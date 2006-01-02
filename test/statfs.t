#!/usr/bin/perl
use test::helper qw($_real $_point);
use Test::More;
require 'syscall.ph'; # for SYS_statfs
plan tests => 7;
my ($statfs_data) = 0x00 x 8 x 16;
my ($tmp) = $_point;
ok(!syscall(&SYS_statfs,$tmp,$statfs_data),"statfs");
# FIXME: this is soooooo linux-centric.  perhaps parse the output of /bin/df?
my @list = unpack("L!7L2L!7",$statfs_data);
diag "statfs: ",join(', ', @list);
shift(@list);
is(shift(@list),4096,"block size");
is(shift(@list),1000000,"blocks");
is(shift(@list),500000,"blocks free");
shift(@list);
is(shift(@list),1000000,"files");
is(shift(@list),500000,"files free");
shift(@list);
shift(@list);
is(shift(@list),255,"namelen");
