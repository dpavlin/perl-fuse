#!/usr/bin/perl
use test::helper qw($_point $_real);
use Test::More;
plan tests => 6;
chdir($_point);
ok(symlink("abc","def"),"symlink created");
ok(-l "def","symlink exists");
is(readlink("def"),"abc","it worked");
chdir($_real);
ok(-l "def","symlink really exists");
is(readlink("def"),"abc","really worked");
unlink("def");

# bug: doing a 'cp -a' on a directory which contains a symlink
# reports an error
mkdir("dira");
open($file, '>', 'dira/filea');
close($file);
symlink('filea', 'dira/fileb');
my $cp = 'cp -a';
if ($^O eq 'netbsd') { $cp = 'cp -R'; }
is(system($cp . " dira dirb")>>8,0,$cp);
map { unlink($_) } ('dira/filea', 'dira/fileb', 'dirb/filea', 'dirb/fileb');
map { rmdir($_) } ('dira', 'dirb');
