use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

my $ver = `fusermount -V`;
my $ver2 = `mount_fusefs -V`;
$ver =~ s/^.*?version:\s+//;
$ver2 =~ s/^.*?version:\s+//;
if (! $ver && ! $ver2) {
	# make CPANPLUS happy and don't report errors if fuse isn't installed
	die("No support for os: $^O\n",
		"You need to have fuse-dev (or similar) package installed and have sufficient permissions in order to install this module\n"
	);
}
if ($ver && $ver + 0 < 2.5) {
	die "Fuse perl bindings need Linux fuse version 2.5 or never\n";
} elsif ($ver2 && $ver2 + 0 < 0.3) {
	die "Fuse perl bindings need FreeBSD fuse version 0.3 or never\n";
} else {
	warn "fuse version found: ", $ver || $ver2, "\n";
}

my $inc = '-DFUSE_USE_VERSION=25 ' . `pkg-config --cflags fuse` || '-I ../include -D_FILE_OFFSET_BITS=64';
my $obj = `pkg-config --libs fuse` || '-lfuse';

WriteMakefile(
	'NAME'			=> 'Fuse',
	'VERSION_FROM'	=> 'Fuse.pm', # finds $VERSION
	'PREREQ_PM'		=> {}, # e.g., Module::Name => 1.1
	($] >= 5.005 ?	## Add these new keywords supported since 5.005
		(ABSTRACT_FROM	=> 'Fuse.pm', # retrieve abstract from module
		AUTHOR			=> 'Mark Glines <mark@glines.org>') : ()),
	'LIBS'			=> [''], # e.g., '-lm'
	'DEFINE'		=> '-Wall -g -ggdb', # e.g., '-DHAVE_SOMETHING'
	# Insert -I. if you add *.h files later:
	'INC'			=> $inc, # e.g., '-I/usr/include/other'
	# Un-comment this if you add C files to link with later:
	'OBJECT'		=> "$obj Fuse.o -lpthread", # link all the C files too
);

sub MY::postamble {
	return <<'MAKE_MORE';

sf:
	svn2cvs.pl file:///home/dpavlin/private/svn/fuse/perl-llin :ext:dpavlin@fuse.cvs.sourceforge.net:/cvsroot/fuse perl

MAKE_MORE
};
