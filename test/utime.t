#!/usr/bin/perl
use lib 'test/lib';
use test::helper qw($_real $_point);
use Test::More;
plan tests => 3;
my (@stat);
chdir($_real);
open($file, '>', 'file');
print($file "frog\n");
close($file);
chdir($_point);
ok(utime(1,2,"file"),"set utime");
@stat = stat("file");
is($stat[8],1,"atime");
is($stat[9],2,"mtime");
unlink("file");
