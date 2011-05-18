package Fuse;

use 5.006;
use strict;
use warnings;
use Errno;
use Carp;
use Config;

require Exporter;
require DynaLoader;
use AutoLoader;
use Data::Dumper;
our @ISA = qw(Exporter DynaLoader);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Fuse ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = (
		    'all' => [ qw(XATTR_CREATE XATTR_REPLACE fuse_get_context fuse_version) ],
		    'xattr' => [ qw(XATTR_CREATE XATTR_REPLACE) ]
		    );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = ();
our $VERSION = '0.11';

sub AUTOLOAD {
    # This AUTOLOAD is used to 'autoload' constants from the constant()
    # XS function.  If a constant is not found then control is passed
    # to the AUTOLOAD in AutoLoader.

    my $constname;
    our $AUTOLOAD;
    ($constname = $AUTOLOAD) =~ s/.*:://;
    croak "& not defined" if $constname eq 'constant';
    my $val = constant($constname, @_ ? $_[0] : 0);
    if ($! != 0) {
	if ($!{EINVAL}) {
	    $AutoLoader::AUTOLOAD = $AUTOLOAD;
	    goto &AutoLoader::AUTOLOAD;
	}
	else {
	    croak "Your vendor has not defined Fuse macro $constname";
	}
    }
    {
	no strict 'refs';
	# Fixed between 5.005_53 and 5.005_61
	if ($] >= 5.00561) {
	    *$AUTOLOAD = sub () { $val };
	}
	else {
	    *$AUTOLOAD = sub { $val };
	}
    }
    goto &$AUTOLOAD;
}

sub XATTR_CREATE {
    # See <sys/xattr.h>.
    return 1;
}

sub XATTR_REPLACE {
    # See <sys/xattr.h>.
    return 2;
}

bootstrap Fuse $VERSION;

sub main {
	my @names = qw(getattr readlink getdir mknod mkdir unlink rmdir symlink
			rename link chmod chown truncate utime open read write statfs
			flush release fsync setxattr getxattr listxattr removexattr);
	my $fuse_version = fuse_version();
	if ($fuse_version >= 2.3) {
		push(@names, qw/opendir readdir releasedir fsyncdir init destroy/);
	}
	if ($fuse_version >= 2.5) {
		push(@names, qw/access create ftruncate fgetattr/);
	}
	if ($fuse_version >= 2.6) {
		push(@names, qw/lock utimens bmap/);
	}
#	if ($fuse_version >= 2.8) {
#		# junk doesn't contain a function pointer, and hopefully
#		# never will; it's a "dead" zone in the struct
#		# fuse_operations where a flag bit is declared. we don't
#		# need to concern ourselves with it, and it appears any
#		# arch with a 64 bit pointer will align everything to
#		# 8 bytes, making the question of pointer alignment for
#		# the last 2 wrapper functions no big thing.
#		push(@names, qw/junk ioctl poll/);
#	}
	my @subs = map {undef} @names;
	my $tmp = 0;
	my %mapping = map { $_ => $tmp++ } @names;
	my @otherargs = qw(debug threaded mountpoint mountopts nullpath_ok);
	my %otherargs = (
			  debug		=> 0,
			  threaded	=> 0,
			  mountpoint	=> "",
			  mountopts	=> "",
			  nullpath_ok	=> 0,
			);
	while(my $name = shift) {
		my ($subref) = shift;
		if(exists($otherargs{$name})) {
			$otherargs{$name} = $subref;
		} else {
			croak "There is no function $name" unless exists($mapping{$name});
			croak "Usage: Fuse::main(getattr => \"main::my_getattr\", ...)" unless $subref;
			$subs[$mapping{$name}] = $subref;
		}
	}
	if($otherargs{threaded}) {
		# make sure threads are both available, and loaded.
		if($Config{useithreads}) {
			if(exists($threads::{VERSION})) {
				if(exists($threads::shared::{VERSION})) {
					# threads will work.
				} else {
					carp("Thread support requires you to use threads::shared.\nThreads are disabled.\n");
					$otherargs{threaded} = 0;
				}
			} else {
				carp("Thread support requires you to use threads and threads::shared.\nThreads are disabled.\n");
				$otherargs{threaded} = 0;
			}
		} else {
			carp("Thread support was not compiled into this build of perl.\nThreads are disabled.\n");
			$otherargs{threaded} = 0;
		}
	}
	perl_fuse_main(@otherargs{@otherargs},@subs);
}

# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__

=head1 NAME

Fuse - write filesystems in Perl using FUSE

=head1 SYNOPSIS

  use Fuse;
  my ($mountpoint) = "";
  $mountpoint = shift(@ARGV) if @ARGV;
  Fuse::main(mountpoint=>$mountpoint, getattr=>"main::my_getattr", getdir=>"main::my_getdir", ...);

=head1 DESCRIPTION

This lets you implement filesystems in perl, through the FUSE
(Filesystem in USErspace) kernel/lib interface.

FUSE expects you to implement callbacks for the various functions.

In the following definitions, "errno" can be 0 (for a success),
-EINVAL, -ENOENT, -EONFIRE, any integer less than 1 really.

You can import standard error constants by saying something like
"use POSIX qw(EDOTDOT ENOANO);".

Every constant you need (file types, open() flags, error values,
etc) can be imported either from POSIX or from Fcntl, often both.
See their respective documentations, for more information.

=head2 EXPORTED SYMBOLS

None by default.

You can request all exportable symbols by using the tag ":all".

You can request the extended attribute symbols by using the tag ":xattr".
This will export XATTR_CREATE and XATTR_REPLACE.

=head2 FUNCTIONS

=head3 Fuse::main

Takes arguments in the form of hash key=>value pairs.  There are
many valid keys.  Most of them correspond with names of callback
functions, as described in section 'FUNCTIONS YOUR FILESYSTEM MAY IMPLEMENT'.
A few special keys also exist:


debug => boolean

=over 1

This turns FUSE call tracing on and off.  Default is 0 (which means off).

=back

mountpoint => string

=over 1

The point at which to mount this filesystem.  There is no default, you must
specify this.  An example would be '/mnt'.

=back

mountopts => string

=over 1

This is a comma seperated list of mount options to pass to the FUSE kernel
module.

At present, it allows the specification of the allow_other
argument when mounting the new FUSE filesystem. To use this, you will also
need 'user_allow_other' in /etc/fuse.conf as per the FUSE documention

  mountopts => "allow_other" or
  mountopts => ""

=back

threaded => boolean

=over 1

This turns FUSE multithreading on and off.  The default is 0, meaning your FUSE
script will run in single-threaded mode.  Note that single-threaded mode also
means that you will not have to worry about reentrancy, though you will have to
worry about recursive lookups.  In single-threaded mode, FUSE holds a global
lock on your filesystem, and will wait for one callback to return before
calling another.  This can lead to deadlocks, if your script makes any attempt
to access files or directories in the filesystem it is providing.  (This
includes calling stat() on the mount-point, statfs() calls from the 'df'
command, and so on and so forth.)  It is worth paying a little attention and
being careful about this.

Enabling multithreading will cause FUSE to make multiple simultaneous calls
into the various callback functions of your perl script.  If you enable 
threaded mode, you can enjoy all the parallel execution and interactive
response benefits of threads, and you get to enjoy all the benefits of race
conditions and locking bugs, too.  Please also ensure any other perl modules
you're using are also thread-safe.

(If enabled, this option will cause a warning if your perl interpreter was not
built with USE_ITHREADS, or if you have failed to use threads or
threads::shared.)

=back

nullpath_ok => boolean

=over 1

This flag tells Fuse to not pass paths for functions that operate on file
or directory handles. This will yield empty path parameters for functions
including read, write, flush, release, fsync, readdir, releasedir,
fsyncdir, truncate, fgetattr and lock. If you use this, you must return
file/directory handles from open, opendir and create. Default is 0 (off).
Only effective on Fuse 2.8 and up; with earlier versions, this does nothing.

=back

=head3 Fuse::fuse_get_context
 
 use Fuse "fuse_get_context";
 my $caller_uid = fuse_get_context()->{"uid"};
 my $caller_gid = fuse_get_context()->{"gid"};
 my $caller_pid = fuse_get_context()->{"pid"};
 
Access context information about the current Fuse operation. 

=head3 Fuse::fuse_version

Indicates the Fuse version in use; more accurately, indicates the version
of the Fuse API in use at build time. Returned as a decimal value; i.e.,
for Fuse API v2.6, will return "2.6".

=head2 FUNCTIONS YOUR FILESYSTEM MAY IMPLEMENT

=head3 getattr

Arguments:  filename.
Returns a list, very similar to the 'stat' function (see
perlfunc).  On error, simply return a single numeric scalar
value (e.g. "return -ENOENT();").

FIXME: the "ino" field is currently ignored.  I tried setting it to 0
in an example script, which consistently caused segfaults.

Fields (the following was stolen from perlfunc(1) with apologies):

($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
        $atime,$mtime,$ctime,$blksize,$blocks)
                         = getattr($filename);

Here are the meaning of the fields:

 0 dev      device number of filesystem
 1 ino      inode number
 2 mode     file mode  (type and permissions)
 3 nlink    number of (hard) links to the file
 4 uid      numeric user ID of file's owner
 5 gid      numeric group ID of file's owner
 6 rdev     the device identifier (special files only)
 7 size     total size of file, in bytes
 8 atime    last access time in seconds since the epoch
 9 mtime    last modify time in seconds since the epoch
10 ctime    inode change time (NOT creation time!) in seconds
            since the epoch
11 blksize  preferred block size for file system I/O
12 blocks   actual number of blocks allocated

(The epoch was at 00:00 January 1, 1970 GMT.)

=head3 readlink

Arguments:  link pathname.
Returns a scalar: either a numeric constant, or a text string.

This is called when dereferencing symbolic links, to learn the target.

example rv: return "/proc/self/fd/stdin";

=head3 getdir

Arguments:  Containing directory name.
Returns a list: 0 or more text strings (the filenames), followed by a numeric errno (usually 0).

This is used to obtain directory listings.  It's opendir(), readdir(), filldir() and closedir() all in one call.

example rv: return ('.', 'a', 'b', 0);

=head3 readdir

Arguments: Directory name, offset
Returns: filename, offset to the next dirent, numeric errno 0 or -ENOENT()

=head3 mknod

Arguments:  Filename, numeric modes, numeric device
Returns an errno (0 upon success, as usual).

This function is called for all non-directory, non-symlink nodes,
not just devices.

=head3 mkdir

Arguments:  New directory pathname, numeric modes.
Returns an errno.

Called to create a directory.

=head3 unlink

Arguments:  Filename.
Returns an errno.

Called to remove a file, device, or symlink.

=head3 rmdir

Arguments:  Pathname.
Returns an errno.

Called to remove a directory.

=head3 symlink

Arguments:  Existing filename, symlink name.
Returns an errno.

Called to create a symbolic link.

=head3 rename

Arguments:  old filename, new filename.
Returns an errno.

Called to rename a file, and/or move a file from one directory to another.

=head3 link

Arguments:  Existing filename, hardlink name.
Returns an errno.

Called to create hard links.

=head3 chmod

Arguments:  Pathname, numeric modes.
Returns an errno.

Called to change permissions on a file/directory/device/symlink.

=head3 chown

Arguments:  Pathname, numeric uid, numeric gid.
Returns an errno.

Called to change ownership of a file/directory/device/symlink.

=head3 truncate

Arguments:  Pathname, numeric offset.
Returns an errno.

Called to truncate a file, at the given offset.

=head3 utime

Arguments:  Pathname, numeric actime, numeric modtime.
Returns an errno.

Called to change access/modification times for a file/directory/device/symlink.

=head3 open

Arguments:  Pathname, numeric flags (which is an OR-ing of stuff like O_RDONLY
and O_SYNC, constants you can import from POSIX), fileinfo hash reference.
Returns an errno, a file handle (optional).

No creation, or trunctation flags (O_CREAT, O_EXCL, O_TRUNC) will be passed to open().
The fileinfo hash reference contains flags from the Fuse open call which may be modified by the module. The only fields presently supported are:
 direct_io (version 2.4 onwards)
 keep_cache (version 2.4 onwards)
 nonseekable (version 2.9 onwards)
Your open() method needs only check if the operation is permitted for the given flags, and return 0 for success.
Optionally a file handle may be returned, which will be passed to subsequent read, write, flush, fsync and release calls.

=head3 read

Arguments:  Pathname, numeric requested size, numeric offset, file handle
Returns a numeric errno, or a string scalar with up to $requestedsize bytes of data.

Called in an attempt to fetch a portion of the file.

=head3 write

Arguments:  Pathname, scalar buffer, numeric offset, file handle.  You can use length($buffer) to
find the buffersize.
Returns length($buffer) if successful (number of bytes written).

Called in an attempt to write (or overwrite) a portion of the file.  Be prepared because $buffer could contain random binary data with NULs and all sorts of other wonderful stuff.

=head3 statfs

Arguments:  none
Returns any of the following:

-ENOANO()

or

$namelen, $files, $files_free, $blocks, $blocks_avail, $blocksize

or

-ENOANO(), $namelen, $files, $files_free, $blocks, $blocks_avail, $blocksize

=head3 flush

Arguments: Pathname, file handle
Returns an errno or 0 on success.

Called to synchronise any cached data. This is called before the file
is closed. It may be called multiple times before a file is closed.

=head3 release

Arguments: Pathname, numeric flags passed to open, file handle
Returns an errno or 0 on success.

Called to indicate that there are no more references to the file. Called once
for every file with the same pathname and flags as were passed to open.

=head3 fsync

Arguments: Pathname, numeric flags
Returns an errno or 0 on success.

Called to synchronise the file's contents. If flags is non-zero,
only synchronise the user data. Otherwise synchronise the user and meta data.

=head3 setxattr

Arguments: Pathname, extended attribute's name, extended attribute's value, numeric flags (which is an OR-ing of XATTR_CREATE and XATTR_REPLACE 
Returns an errno or 0 on success.

Called to set the value of the named extended attribute.

If you wish to reject setting of a particular form of extended attribute name
(e.g.: regexps matching user\..* or security\..*), then return - EOPNOTSUPP.

If flags is set to XATTR_CREATE and the extended attribute already exists,
this should fail with - EEXIST. If flags is set to XATTR_REPLACE
and the extended attribute doesn't exist, this should fail with - ENOATTR.

XATTR_CREATE and XATTR_REPLACE are provided by this module, but not exported
by default. To import them:

    use Fuse ':xattr';

or:

    use Fuse ':all';

=head3 getxattr

Arguments: Pathname, extended attribute's name
Returns an errno, 0 if there was no value, or the extended attribute's value.

Called to get the value of the named extended attribute.

=head3 listxattr

Arguments: Pathname
Returns a list: 0 or more text strings (the extended attribute names), followed by a numeric errno (usually 0).

=head3 removexattr

Arguments: Pathname, extended attribute's name
Returns an errno or 0 on success.

=head3 opendir

Arguments: Pathname of a directory
Returns an errno, and a directory handle (optional)

Called when opening a directory for reading. If special handling is
required to open a directory, this operation can be implemented to handle
that.

=head3 readdir

Arguments: Pathname of a directory, numeric offset, (optional) directory handle
Returns a list of 0 or more entries, followed by a numeric errno (usually 0).
The entries can be simple strings (filenames), or arrays containing an
offset number, the filename, and optionally an array ref containing the
stat values (as would be returned from getattr()).

This is used to read entries from a directory. It can be used to return just
entry names like getdir(), or can get a segment of the available entries,
which requires using array refs and the 2- or 3-item form, with offset values
starting from 1. If you wish to return the parameters to fill each entry's
struct stat, but do not wish to do partial entry lists/entry counting, set
the first element of each array to 0 always.

Note that if this call is implemented, it overrides getdir() ALWAYS.

=head3 releasedir

Arguments: Pathname of a directory, (optional) directory handle
Returns an errno or 0 on success

Called when there are no more references to an opened directory. Called once
for each pathname or handle passed to opendir(). Similar to release(), but
for directories. Accepts a return value, but like release(), the response
code will not propagate to any corresponding closedir() calls.

=head3 fsyncdir

Arguments: Pathname of a directory, numeric flags, (optional) directory handle
Returns an errno or 0 on success.

Called to synchronize any changes to a directory's contents. If flag is
non-zero, only synchronize user data, otherwise synchronize user data and
metadata.

=head3 init

Arguments: None.
Returns (optionally) an SV to be passed as private_data via fuse_get_context().

=head3 destroy

Arguments: (optional) private data SV returned from init(), if any.
Returns nothing.

=head3 access

Arguments: Pathname, access mode flags
Returns an errno or 0 on success.

Determine if the user attempting to access the indicated file has access to
perform the requested actions. The user ID can be determined by calling
fuse_get_context(). See access(2) for more information.

=head3 create

Arguments: Pathname, create mask, open mode flags
Returns errno or 0 on success, and (optional) file handle.

Create a file with the path indicated, then open a handle for reading and/or
writing with the supplied mode flags. Can also return a file handle like
open() as part of the call.

=head3 ftruncate

Arguments: Pathname, numeric offset, (optional) file handle
Returns errno or 0 on success

Like truncate(), but on an opened file.

=head3 fgetattr

Arguments: Pathname, (optional) file handle
Returns a list, very similar to the 'stat' function (see
perlfunc).  On error, simply return a single numeric scalar
value (e.g. "return -ENOENT();").

Like getattr(), but on an opened file.

=head3 lock

Arguments: Pathname, numeric command code, hashref containing lock parameters, (optional) file handle
Returns errno or 0 on success

Used to lock or unlock regions of a file. Locking is handled locally, but this
allows (especially for networked file systems) for protocol-level locking
semantics to also be employed, if any are available.

See the Fuse documentation for more explanation of lock(). The needed symbols
for the lock constants can be obtained by importing Fcntl.

=head3 utimens

Arguments: Pathname, last accessed time, last modified time
Returns errno or 0 on success

Like utime(), but allows time resolution down to the nanosecond. Currently
times are passed as "numeric" (internally I believe these are represented
typically as "long double"), so the sub-second portion is represented as
fractions of a second.

Note that if this call is implemented, it overrides utime() ALWAYS.

=head3 bmap

Arguments: Pathname, numeric blocksize, numeric block number
Returns errno or 0 on success, and physical block number if successful

Used to map a block number offset in a file to the physical block offset
on the block device backing the file system. This is intended for
filesystems that are stored on an actual block device, with the 'blkdev'
option passed.

=head1 AUTHOR

Mark Glines, E<lt>mark@glines.orgE<gt>

=head1 SEE ALSO

L<perl>, the FUSE documentation.

=cut
