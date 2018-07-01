#!/usr/bin/perl
use lib 'test/lib';
use test::helper qw($_real $_point);
use Test::More;
plan tests => 3;
chdir($_real);
open($file, '>','file');
print $file "frog\n";
close($file);
chdir($_point);
ok(open(FILE,"file"),"open");
my ($data) = <FILE>;
close(FILE);
is(length($data),5,"right amount read");
is($data,"frog\n","right data read");
unlink("file");
