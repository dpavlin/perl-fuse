use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

my $inc = '-DFUSE_USE_VERSION=25 ' . `pkg-config --cflags fuse` || '-I ../include -D_FILE_OFFSET_BITS=64';
my $obj = `pkg-config --libs fuse` || '-lfuse';
 
WriteMakefile(
    'NAME'		=> 'Fuse',
    'VERSION_FROM'	=> 'Fuse.pm', # finds $VERSION
    'PREREQ_PM'		=> {}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'Fuse.pm', # retrieve abstract from module
       AUTHOR     => 'Mark Glines <mark@glines.org>') : ()),
    'LIBS'		=> [''], # e.g., '-lm'
    'DEFINE'		=> '-g -ggdb', # e.g., '-DHAVE_SOMETHING'
	# Insert -I. if you add *.h files later:
    'INC'		=> $inc, # e.g., '-I/usr/include/other'
	# Un-comment this if you add C files to link with later:
    'OBJECT'		=> "$obj Fuse.o -lpthread", # link all the C files too
);

sub MY::postamble {
    return <<'MAKE_MORE';

sf:
	svn2cvs.pl file:///home/dpavlin/.svk/fuse/perl-llin :ext:dpavlin@cvs.sourceforge.net:/cvsroot/fuse perl

MAKE_MORE
};
