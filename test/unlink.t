#!/usr/bin/perl
use lib 'test/lib';
use test::helper qw($_real $_point);
use Test::More;
plan tests => 4;
chdir($_point);
open($file, '>', 'file');
close($file);
ok(-f "file","file exists");
chdir($_real);
ok(-f "file","file really exists");
chdir($_point);
unlink("file");
ok(! -f "file","file unlinked");
chdir($_real);
ok(! -f "file","file really unlinked");
