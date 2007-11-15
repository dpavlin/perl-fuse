#!/usr/bin/perl -w
use test::helper qw($_point $_loop $_real $_pidfile);
use strict;
use Test::More tests => 3;
ok(!(scalar grep(/ on $_point /,`cat /proc/mounts`)),"already mounted");
ok(-f $_loop,"loopback exists");

if(!fork()) {
	#close(STDIN);
	close(STDOUT);
	close(STDERR);
	mkdir $_point;
	mkdir $_real;
	`echo $$ >test/s/mounted.pid`;
	diag "mounting $_loop to $_point";
	exec("perl -Iblib/lib -Iblib/arch $_loop $_point");
	exit(1);
}

my ($success, $count) = (0,0);
while ($count++ < 50 && !$success) {
	select(undef, undef, undef, 0.1);
	   ($success) = `mount` =~ / $_point /;
}
diag "Mounted in ", $count/10, " secs";

ok($success,"mount succeeded");
system("rm -rf $_real");
unless($success) {
	kill('INT',`cat $_pidfile`);
	unlink($_pidfile);
} else {
	mkdir($_real);
}
