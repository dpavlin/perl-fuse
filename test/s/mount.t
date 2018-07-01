#!/usr/bin/perl -w
use lib 'test/lib';
use test::helper qw($_point $_loop $_opts $_real $_pidfile $_logfile);
use strict;
use Errno qw(:POSIX);
use Test::More tests => 3;

sub is_mounted {
	my $diag = -e '/proc/mounts' ? `cat /proc/mounts` : ($^O eq 'linux' ? `/bin/mount` : ($^O eq 'solaris' ? `/usr/sbin/mount` : `/sbin/mount`));
	my $pattern = $^O eq 'solaris' ? qr{^$_point }m : qr{ (?:/private)?$_point };
	return $diag =~ $pattern;
}

ok(!is_mounted(),"not already mounted");
ok(-f $_loop,"loopback exists");

mkdir $_point;
mkdir $_real;
diag "mounting $_loop to $_point with $_opts";
open REALSTDOUT, '>&STDOUT';
open REALSTDERR, '>&STDERR';
open STDOUT, '>', '/dev/null';
open STDERR, '>&', \*STDOUT;
system("perl -Iblib/lib -Iblib/arch $_loop $_opts $_point");
open STDOUT, '>&', \*REALSTDOUT;
open STDERR, '>&', \*REALSTDERR;

my ($success, $count) = (0,0);
while ($count++ < 50 && !$success) {
	select(undef, undef, undef, 0.1);
	($success) = is_mounted();
}

ok( $success, "mount succeeded" );
system("rm -rf $_real");

if ($success) {
    diag "mounted in " . $count/10 . " secs";
	mkdir($_real);
}
else {
    if (-e $_logfile) {
        my $errors = `cat $_logfile`;
        diag "error mounting $_loop:\n$errors";
        unlink $_logfile;
    }
    if (-e $_pidfile) {
        kill('INT',`cat $_pidfile`);
        unlink($_pidfile);
    }
}
