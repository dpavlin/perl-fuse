#!/usr/bin/perl
use lib 'test/lib';
use test::helper qw($_real $_point);
use Test::More;
plan tests => 8;
chdir($_point);
open($file, '>', 'womble');
print $file "hippity\n";
close($file);
ok(-f "womble","exists");
ok(!-f "rabbit","target file doesn't exist");
is(-s "womble",8,"right size");
ok(link("womble","rabbit"),"link");
ok(-f "womble","old file exists");
ok(-f "rabbit","target file exists");
is(-s "womble",8,"right size");
is(-s "rabbit",8,"right size");
unlink("womble");
unlink("rabbit");
