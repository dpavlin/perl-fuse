use ExtUtils::MakeMaker;
use POSIX;
use Config;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

# Note: This is a hack. This hack is necessary because MacFUSE's libfuse
# (and libfuse_ino64, by extension) don't link in libiconv. This wouldn't
# be a problem, but it appears the Darwin/OS X dynamic linker won't
# satisfy runtime link dependencies in those libraries from libraries
# imported by our library, and it uses a symbol from libiconv without
# actually linking the library to itself. Awesome.
package MY;
sub test_via_harness {
    my($self, $perl, $tests) = @_;
    local $_ = $self->SUPER::test_via_harness($perl, $tests);
    s/PERL_DL_NONLAZY=1//g if $^O eq 'darwin';
    return $_;
}

sub test_via_script {
    my($self, $perl, $tests) = @_;
    local $_ = $self->SUPER::test_via_script($perl, $tests);
    s/PERL_DL_NONLAZY=1//g if $^O eq 'darwin';
    return $_;
}

package main;

chomp(my $fusever = `pkg-config --modversion fuse 2> /dev/null`);
# Required for refuse on NetBSD
if (!$fusever && $^O eq 'netbsd') {
    chomp($fusever = `fusermount -V`);
    $fusever =~ s/^.*?version:\s+//;
}

unless ($fusever) {
    # make CPANPLUS happy and don't report errors if fuse isn't installed
    my $explanation;
    if ($^O eq 'linux') {
        if (-e '/etc/debian_version') {
            $explanation = 'You need to install "libfuse-dev" to provide build support for this module';
        }
        elsif (-e '/etc/redhat-release') {
            $explanation = 'You need to install "fuse-devel" to provide build support for this module';
        }
        else {
            $explanation = 'I don\'t know your Linux distribution, but please install the FUSE libraries and headers to build this module';
        }
    }
    elsif ($^O eq 'freebsd') {
        $explanation = 'You need to install the "fusefs-libs" package from ports to support this module';
    }
    elsif ($^O eq 'netbsd') {
        $explanation = 'Could not find librefuse? Maybe install "perfuse" from pkgsrc, or upgrade to newer NetBSD';
    }
    elsif ($^O eq 'darwin') {
        $explanation = 'Please install OSXFUSE from http://osxfuse.github.com/';
    }
    elsif ($^O eq 'solaris') {
        open(my $motd, '<', '/etc/motd');
        my $line = <$motd>;
        if ($line =~ /^OpenIndiana /) {
            $explanation = 'Please enable the \'sfe\' repository, and install the libfuse package';
        }
        else {
            $explanation = 'Don\'t know how to enable FUSE support on this Solaris flavor';
        }
    }
    elsif ($^O eq 'openbsd') {
        $explanation = 'Please see README for information about OpenBSD FUSE support';
    }
    else {
        $explanation = 'There is no FUSE support for your platform to our knowledge, sorry';
    }
    die("Cannot build for platform: $^O\n", $explanation, "\n");
}
if ($fusever && $fusever + 0 < 2.6) {
    die "FUSE API is ", $fusever, ", must be 2.6 or later\n";
} else {
    warn "fuse version found: ", $fusever, "\n";
}

chomp(my $inc = `pkg-config --cflags-only-I fuse 2> /dev/null`);
chomp(my $libs = `pkg-config --libs-only-L fuse 2> /dev/null`);
chomp($libs .= `pkg-config --libs-only-l fuse 2> /dev/null` || (($^O eq 'netbsd') ? '-lrefuse' : '-lfuse'));
# Needed for Fuse on OS X 10.6, due to 10.6 and up always using the 64-bit
# inode structs; unfortunately MacFuse doesn't just do the right thing
# on its own. (Not applicable for OSXFUSE; it uses a new SONAME, so we
# don't have to worry about conflicts/compatibility, it "just works".)
if ($^O eq 'darwin' && (uname())[2] =~ /^1[01]\./) {
    $libs =~ s/-lfuse\b/-lfuse_ino64/;
}
chomp(my $def = '-Wall -DFUSE_USE_VERSION=26 ' . `pkg-config --cflags-only-other fuse 2> /dev/null` || '-D_FILE_OFFSET_BITS=64');
chomp($def .= `pkg-config --libs-only-other fuse 2> /dev/null`);
$def .= ' -DPERL_HAS_64BITINT' if $Config{'use64bitint'};
$def .= ' -DUSING_LIBREFUSE' if $libs =~ m{-lrefuse\b};

# As a feature was added in a micro version update (fallocate(),
# specifically), we need to know the micro version level, and there's
# nothing in the headers that supplies it, so I'm gonna ghetto this
# up.
my ($major, $minor, $micro) = split(m{\.}, $fusever);
if ($^O eq 'openbsd') {
    # Note: This is a hack. Unfortunately OpenBSD's FUSE lies in its
    # pkgconfig and claims to be FUSE 2.8, when it only supplies the
    # FUSE 2.6 API. This breaks the module, so I'm going to work around
    # that for now...
    $minor = 6;
}
if (!defined $micro) {
    $micro = 0;
}
$def .= ' -DFUSE_FOUND_MAJOR_VER=' . $major;
$def .= ' -DFUSE_FOUND_MINOR_VER=' . $minor;
$def .= ' -DFUSE_FOUND_MICRO_VER=' . $micro;

WriteMakefile(
    'NAME'          => 'Fuse',
    'VERSION_FROM'  => 'Fuse.pm', # finds $VERSION
    'PREREQ_PM'     => { # e.g., Module::Name => 1.1
        'Lchown'            => 0,
        'Filesys::Statvfs'  => 0,
        'Unix::Mknod'       => 0,
    },
    ($] >= 5.005 ?  ## Add these new keywords supported since 5.005
       (ABSTRACT_FROM   => 'Fuse.pm', # retrieve abstract from module
        AUTHOR          => 'Mark Glines <mark@glines.org>') : ()),
    ($ExtUtils::MakeMaker::VERSION < 6.3002 ? () : (
        'LICENSE' => 'LGPL_2_1',
    )),
    ($ExtUtils::MakeMaker::VERSION < 6.46 ? () : (
        META_MERGE => {
            resources => {
                license => 'http://www.gnu.org/licenses/lgpl-2.1.html',
                bugtracker => 'https://rt.cpan.org/Public/Dist/Display.html?Name=Fuse',
                repository => 'http://github.com/dpavlin/perl-fuse'
            },
        })
    ),
    'LIBS'          => $libs, # e.g., '-lm'
    'DEFINE'        => $def, # e.g., '-DHAVE_SOMETHING'
    'OPTIMIZE'      => '-g -ggdb',
    # Insert -I. if you add *.h files later:
    'INC'           => $inc, # e.g., '-I/usr/include/other'
    # Un-comment this if you add C files to link with later:
    'OBJECT'        => 'Fuse$(OBJ_EXT)', # link all the C files too
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

# vim: ts=4 ai et hls
