Fuse Perl bindings
==================

This module lets you implement filesystems in Perl, through the
[FUSE](http://fuse.sourceforge.net) (Filesystem in USErspace)
kernel/lib interface.

```perl
  use Fuse;

  Fuse::main(
      mountpoint => '/mnt/my_fs',
      threaded   => 0,
      debug      => 1,

      getattr    => sub { ... }, # fetches attributes, like 'stat'
      getdir     => sub { ... }, # obtains directory listings
      open       => sub { ... }, # opens files
      statfs     => sub { ... }, # returns filesystem data
      read       => sub { ... }, # reads file contents

      # there are many more you can implement!
  );
```

See [Fuse's main documentation](https://metacpan.org/pod/distribution/Fuse/Fuse.pm)
for more details.

#### Installation ####

This module requires the FUSE C library and the FUSE kernel module,
both available at http://fuse.sourceforge.net. It should work with
versions 2.6 and up.

There are pre-built packages for FUSE in major operating systems:

**Debian:** `sudo apt-get install libfuse-dev`

**RedHat:** `sudo yum install fuse-devel`

**OSX:** install [OSXFUSE](http://osxfuse.github.com) manually
or via homebrew `brew install osxfuse`

**Solaris:** enable the 'sfe' repository, then install `libfuse`

FUSE is also available on the main BSD flavours, but please see the
notes below for extra information:

**FreeBSD:** install `fusefs-libs` from ports

**NetBSD:** install `librefuse` or `perfuse` from pkgsrc

**OpenBSD:** (see below)

If you intend to use FUSE in threaded mode, you need a version of perl
compiled with USE_ITHREADS. Then, you need to use threads and
threads::shared.

After installing the external libraries, you can install the Fuse module
using you favorite CPAN tool. For example:

    cpanm Fuse

Or manually, by downloading, unpacking and typing:

    perl Makefile.PL
    make
    make test
    make install


#### EXAMPLES ####

We have bundled a few example scripts in the examples/
subdirectory. These are:

* example.pl, a simple "Hello world" type of script

* loopback.pl, a filesystem loopback-device. Like fusexmp from
               the main FUSE dist, it simply recurses file operations
               into the real filesystem. However, unlike fusexmp, it only
               re-shares files under the /tmp/test directory.

* rmount.pl, an NFS-workalike which tunnels through SSH. It requires
             an account on some ssh server (obviously) with public-key
             authentication enabled (if you have to type in a password,
             you don't have this. See *man ssh_keygen* for more information).
             Copy rmount_remote.pl to your home directory on the remote
             machine, and create a subdir somewhere, and then run it like:
             ./rmount.pl host /remote/dir /local/dir

* rmount_remote.pl, a ripoff of loopback.pl meant to be used as a backend
                    for rmount.pl.

### Happy FUSEing! ###


#### Notes for BSD users ####

On NetBSD, there is a potential issue with readdir() only being called
once when using librefuse. However, currently using Perfuse causes other
issues (readlink() drops the last character from the read link path, and
the block count in stat() is incorrect). We will be addressing these
concerns with the appropriate developers in the near future.

If you are using Perfuse on NetBSD, you should do the following (as root):

    cat >> /etc/sysctl.conf <<_EOT_
    kern.sbmax=2621440
    net.inet.tcp.sendbuf_max=2621440
    net.inet6.tcp6.sendbuf_max=2621440
    _EOT_
    sysctl -f /etc/sysctl.conf

Perfuse uses TCP sockets, and needs large send buffers.

On NetBSD and FreeBSD, extended attributes do not work. These are
specifically related to the FUSE implementations on those platforms.

Normally you can not mount FUSE filesystems as non-root users on FreeBSD
and NetBSD. They can allow non-root users to mount FUSE filesystems, but
instead of changing the mode of /dev/fuse or /bin/fusermount, you need
to use sysctl to allow user mounts. For FreeBSD, this involves (as root):

    sysctl -w vfs.usermount=1
    pw usermod <your username here> -G operator

And on NetBSD (also as root):

    sysctl -w vfs.generic.usermount=1
    chmod 0660 /dev/putter
    usermod -G wheel <your username here>


#### Notes for OpenBSD in particular ####

While it still has some known issues, FUSE has actually made its way
onto OpenBSD.

As of this writing, OpenBSD includes a BSD-licensed reimplementation
of libfuse, and their own fuse kernel driver. It is available at better
OpenBSD mirrors everywhere.

Keep in mind that if you want thread support (some Fuse filesystems do
require it), the Perl build in OpenBSD 5.6 base does *not* support threads.
Assuming you're not an OpenBSD ninja (or completely insane), I don't
recommend trying to build your own and install it over the system Perl,
because that can have bad repercussions. Use something like
[perlbrew](http://perlbrew.pl) if you want a threaded Perl:

    perlbrew install perl-<version> -Dusethreads \
       --as perl-<version>_WITH_THREADS


For the tests, I recommend installing devel/p5-Lchown,
devel/p5-Filesys-Statvfs, devel/p5-Unix-Mknod and devel/p5-Test-Pod from
OpenBSD ports. (Or use the 'cpan' command from your Perlbrew-installed
version to install those modules, if you want thread support like I was
talking about above.)

Now, in your perl-fuse distribution, run:

    perl Makefile.PL
    make

You'll probably need to 'make test' as root. If you want to run your FUSE
filesystem as non-root, run the following (as root):

    sysctl kern.usermount=1
    chmod 0660 /dev/fuse0

Now, you should be able to run 'make test'. Yes, there are a few test
failures. No, those actually aren't our fault. Here are some things
you should know about the state of FUSE on OpenBSD (the developer,
Sylvestre Gallon, has been made aware of these):

 * There is a bug if a file is created in the fuse filesystem and goes
   away, then you create another file of the same name via FUSE and
   try to do utime(). Not sure if it's just utime() or if other things
   trip it too, but I discovered that via playing around. I *THINK*
   it's a vnode caching problem.
 * There is also a known issue with access() if all parent directories
   of a path haven't been explicitly accessed first.
 * There is a known issue with readdir() when supplying numbered dirents
   to support progressive readdir().
 * You should probably implement all of chown(), chmod(), truncate(), and
   utime() and/or utimens(). The kernel driver will mask out future
   setattr() requests if it gets ENOSYS from ANY of these. Oops.


#### COPYRIGHT AND LICENCE ####

This is contributed to the FUSE project by Mark Glines <mark@glines.org>,
and is therefore subject to the same license and copyright as FUSE itself.
It is released under LGPL 2.1. Please see the AUTHORS and COPYING files
from the FUSE distribution for more information.

