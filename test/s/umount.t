#!/usr/bin/perl
use lib 'test/lib';
use test::helper qw($_point $_real $_pidfile);
use strict;
use Test::More tests => 1;
use POSIX qw(WEXITSTATUS);
system("fusermount -u $_point");
if(POSIX::WEXITSTATUS($?) != 0) {
	system("umount $_point");
}
ok(POSIX::WEXITSTATUS($?) == 0,"unmount");
system("rm -rf $_real $_pidfile");
rmdir($_point);
