#!/usr/bin/perl
package # avoid cpan indexing
	test::helper;
use strict;
use Exporter;
use Config;
use POSIX qw(WEXITSTATUS);
our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
@ISA = "Exporter";
@EXPORT_OK = qw($_loop $_opts $_point $_pidfile $_real $_logfile);
my $tmp = -d '/private' ? '/private/tmp' : '/tmp';

our $_loop    = 'examples/loopback.pl';
our $_point   = "$tmp/fusemnt-".$ENV{LOGNAME};
our $_pidfile = $ENV{'PWD'} . "/test/s/mounted.pid";
our $_real    = "$tmp/fusetest-".$ENV{LOGNAME};
our $_opts    = '';
our $_logfile = "$tmp/fusemnt.log";

$_opts  = ' --pidfile ' . $_pidfile;
$_opts .= ' --logfile ' . $_logfile;
$_opts .= $Config{useithreads} ? ' --use-threads' : '';

if($0 !~ qr|s/u?mount\.t$|) {
	my ($reject) = 1;
	if(open my $fh, '<', $_pidfile) {
		my $pid = do {local $/ = undef; <$fh>};
		close $fh;
		if(kill 0, $pid) {
			my $pattern = $^O eq 'solaris' ? qr{^$_point on }m : qr{on (?:/private)?$_point };
			if(`mount` =~ $pattern) {
				$reject = 0;
			} else {
				kill 1, $pid;
			}
		}
	}
	system("ls $_point >/dev/null");
	$reject = 1 if (POSIX::WEXITSTATUS($?));
	die "not properly mounted\n" if $reject;
}
1;
