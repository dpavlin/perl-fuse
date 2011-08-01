#!/usr/bin/perl
use test::helper qw($_real $_point);
use Test::More;
plan tests => 1;
chdir($_real);
open($file, '>', 'file');
print $file "frog\n";
close($file);
chdir($_point);
ok(open(FILE,"file"),"open");
close(FILE);
unlink("file");
