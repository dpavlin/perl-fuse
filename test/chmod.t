#!/usr/bin/perl
use lib 'test/lib';
use test::helper qw($_real $_point);
use Test::More;
plan tests => 4;
chdir($_point);
open($file, '>', 'file');
print $file "frog\n";
close($file);
ok(chmod(0644,"file"),"set unexecutable");
ok(!-x "file","unexecutable");
ok(chmod(0755,"file"),"set executable");
ok(-x "file","executable");
unlink("file");
