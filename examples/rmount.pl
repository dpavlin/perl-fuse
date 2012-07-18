#!/usr/bin/perl -w

# This example needs some work before it can support threads.
use strict;
use Net::SSH 'sshopen2';
use IPC::Open2;
use Fuse;
use Data::Dumper;

my $port; if($ARGV[-1]=~/^--/){ $port = pop(@ARGV); $port =~ s/--port=//; }
my ($host, $dir, $mount) = @ARGV;
if(!defined($mount)) {
	$mount = $dir;
	if($host =~ /^(.*):(.*)$/) {
		($host,$dir) = ($1,$2);
	} else {
		die "usage: $0 user\@host remotedir mountpoint [--port=<port>]\n".
		    "or   : $0 user\@host:remotedir mountpoint [--port=<port>]\n";
	}
}

`umount $mount` unless -d $mount;
die "mountpoint $mount isn't a directory!\n" unless -d $mount;

my (%args) = (mountpoint => $mount);

map { my ($str) = $_; $args{$str} = sub { netlink($str,@_) } }
	qw(getattr getdir open read write readlink unlink rmdir
	   symlink rename link chown chmod truncate utime mkdir
	   rmdir mknod statfs);

sub connect_remote {
	push(@Net::SSH::ssh_options, "-p $port") if $port;
	sshopen2($host, *READER, *WRITER, "./rmount_remote.pl $dir")
		or die "ssh: $!\n";
	select WRITER;
	$| = 1;
	select STDOUT;
}

$SIG{CHLD} = sub {
	use POSIX ":sys_wait_h";
	my $kid;
	do {
		$kid = waitpid(-1,WNOHANG);
	} until $kid < 1;
};

connect_remote;

sub netlink {
	my ($str) = Dumper(\@_)."\n";
	$str = sprintf("%08i\n%s",length($str),$str);
	while(1) { # retry as necessary
		my ($VAR1);
		$VAR1 = undef;
		eval {
			local $SIG{ALRM} = sub { die "timeout\n" };
			alarm 10;
			print WRITER $str;
			my ($len, $data);
			$data = '';
			if(sysread(READER,$len,9) == 9) {
				sysread(READER,$data,$len-length($data),length($data))
					while(length($data) < $len);
				eval $data;
			}
			alarm 0;
		};
		if(defined $VAR1) {
			return wantarray ? @{$VAR1} : $$VAR1[0];
		}
		print STDERR "failed to send command; reconnecting ssh\n";
		close(READER);
		close(WRITER);
		connect_remote();
	}
}

Fuse::main(%args);

netlink("bye");
close(READER);
close(WRITER);
