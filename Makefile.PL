use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

my $ver = `fusermount -V`;
my $ver2 = `mount_fusefs -V`;
chomp(my $ver3 = `mount_fusefs -V 2>&1 | head -n1`);
$ver =~ s/^.*?version:\s+//;
$ver2 =~ s/^.*?version:\s+//;
$ver3 =~ s/^.*?version\s+//;
if (! $ver && ! $ver2 && ! $ver3) {
	# make CPANPLUS happy and don't report errors if fuse isn't installed
	die("No support for os: $^O\n",
		"You need to have fuse-dev (or similar) package installed and have sufficient permissions in order to install this module\n",
		$^O eq 'darwin' ? ("One option on Mac is http://code.google.com/p/macfuse/\n") : (),
	);
}
if ($ver && $ver + 0 < 2.5) {
	die "Fuse perl bindings need Linux fuse version 2.5 or newer\n";
} elsif ($ver2 && $ver2 + 0 < 0.3) {
	die "Fuse perl bindings need FreeBSD fuse version 0.3 or newer\n";
} elsif ($^O eq 'darwin' && $ver3 && !(($ver3 ge "0.1.0b006") || ($ver3 eq "0.1.0"))) {
	# the "ge" string-compare check will match all later revs and all later
	# betas, but not the final release of the current rev (0.1.0).
	die "Fuse perl bindings need MacFUSE version 0.1.0b006 or newer, your version is \"$ver3\"\n";
} else {
	warn "fuse version found: ", $ver || $ver2 || $ver3, "\n";
}

my $inc = '-DFUSE_USE_VERSION=25 ' . `pkg-config --cflags fuse` || '-I ../include -D_FILE_OFFSET_BITS=64';
my $obj = `pkg-config --libs fuse` || '-lfuse';
my $def = '-Wall -g -ggdb';
$def .= ' -D__FreeBSD__=10 -D_FILE_OFFSET_BITS=64' if $^O eq 'darwin';

WriteMakefile(
	'NAME'			=> 'Fuse',
	'VERSION_FROM'	=> 'Fuse.pm', # finds $VERSION
	'PREREQ_PM'		=> {}, # e.g., Module::Name => 1.1
	($] >= 5.005 ?	## Add these new keywords supported since 5.005
		(ABSTRACT_FROM	=> 'Fuse.pm', # retrieve abstract from module
		AUTHOR			=> 'Mark Glines <mark@glines.org>') : ()),
		($ExtUtils::MakeMaker::VERSION < 6.46 ? () : (
			META_MERGE => {
				resources => {
				bugtracker => 'https://rt.cpan.org/Public/Dist/Display.html?Name=Fuse',
				repository => 'http://github.com/dpavlin/perl-fuse'
			}
   		})
	),
	'LIBS'			=> [''], # e.g., '-lm'
	'DEFINE'		=> $def, # e.g., '-DHAVE_SOMETHING'
	# Insert -I. if you add *.h files later:
	'INC'			=> $inc, # e.g., '-I/usr/include/other'
	# Un-comment this if you add C files to link with later:
	'OBJECT'		=> "$obj Fuse.o -lpthread", # link all the C files too
);

sub MY::postamble {
	return <<'MAKE_MORE';

cpan:
	make clean
	rm -f Fuse-*.tar.gz
	perl Makefile.PL
	make dist
	make disttest
	@echo
	@echo -n "Upload" Fuse-*.tar.gz "to CPAN? [y/N]:"
	@read upload && test "$$upload" == "y" && cpan-upload -verbose Fuse-*.tar.gz



sf:
	svn2cvs.pl file:///home/dpavlin/private/svn/fuse/perl-llin :ext:dpavlin@fuse.cvs.sourceforge.net:/cvsroot/fuse perl

MAKE_MORE
};
