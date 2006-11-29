#!/usr/bin/perl
package test::helper;
use strict;
use Exporter;
use Config;
use POSIX qw(WEXITSTATUS);
our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
@ISA = "Exporter";
@EXPORT_OK = qw($_loop $_point $_pidfile $_real);
our($_loop, $_point, $_pidfile, $_real) = ("","/tmp/fusemnt-".$ENV{LOGNAME},"test/s/mounted.pid","/tmp/fusetest-".$ENV{LOGNAME});
$_loop = $Config{useithreads} ? "examples/loopback_t.pl" : "examples/loopback.pl";
if($0 !~ qr|s/u?mount\.t$|) {
	my ($reject) = 1;
	if(-f $_pidfile) {
		unless(POSIX::WEXITSTATUS(system("ps `cat $_pidfile` | grep \"$_loop $_point\" >/dev/null"))) {
			if(`mount | grep "on $_point"`) {
				$reject = 0;
			} else {
				system("kill `cat $_pidfile`");
			}
		}
	}
	system("ls $_point >/dev/null");
	$reject = 1 if (POSIX::WEXITSTATUS($?));
	die "not properly mounted\n" if $reject;
}
1;
