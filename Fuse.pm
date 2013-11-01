package Fuse;

use 5.006;
use strict;
use warnings;
use Errno;
use Carp;
use Config;
use List::Util qw(sum);

require Exporter;
require DynaLoader;
use AutoLoader;
our @ISA = qw(Exporter DynaLoader);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Fuse ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = (
		    'all' => [ qw(FUSE_BUF_IS_FD FUSE_BUF_FD_SEEK FUSE_BUF_FD_RETRY UTIME_NOW UTIME_OMIT XATTR_CREATE XATTR_REPLACE fuse_get_context fuse_version fuse_buf_copy fuse_buf_size FUSE_IOCTL_COMPAT FUSE_IOCTL_UNRESTRICTED FUSE_IOCTL_RETRY FUSE_IOCTL_MAX_IOV notify_poll pollhandle_destroy) ],
		    'xattr' => [ qw(XATTR_CREATE XATTR_REPLACE) ],
		    'utime' => [ qw(UTIME_NOW UTIME_OMIT) ],
		    'zerocopy' => [ qw(FUSE_BUF_IS_FD FUSE_BUF_FD_SEEK FUSE_BUF_FD_RETRY) ],
		    'ioctl' => [ qw(FUSE_IOCTL_COMPAT FUSE_IOCTL_UNRESTRICTED FUSE_IOCTL_RETRY FUSE_IOCTL_MAX_IOV) ],
		    );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = ();
our $VERSION = '0.16_1';

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

bootstrap Fuse $VERSION;

use constant FUSE_IOCTL_COMPAT		=> (1 << 0);
use constant FUSE_IOCTL_UNRESTRICTED	=> (1 << 1);
use constant FUSE_IOCTL_RETRY		=> (1 << 2);
use constant FUSE_IOCTL_MAX_IOV		=> 256;

sub main {
	my @names = qw(getattr readlink getdir mknod mkdir unlink rmdir symlink
			rename link chmod chown truncate utime open read write statfs
			flush release fsync setxattr getxattr listxattr removexattr
			opendir readdir releasedir fsyncdir init destroy access
			create ftruncate fgetattr lock utimens bmap);
	my ($fuse_vmajor, $fuse_vminor, $fuse_vmicro) = fuse_version();
	my $fuse_version = $fuse_vmajor + ($fuse_vminor * 1.0 / 1_000) +
		($fuse_vmicro * 1.0 / 1_000_000);
	if ($fuse_version >= 2.008) {
		# junk doesn't contain a function pointer, and hopefully
		# never will; it's a "dead" zone in the struct
		# fuse_operations where a flag bit is declared. we don't
		# need to concern ourselves with it, and it appears any
		# arch with a 64 bit pointer will align everything to
		# 8 bytes, making the question of pointer alignment for
		# the last 2 wrapper functions no big thing.
		push(@names, qw/junk ioctl poll/);
	}
	if ($fuse_version >= 2.009) {
		push(@names, qw/write_buf read_buf flock/);
	}
	if ($fuse_version >= 2.009001) {
		push(@names, qw/fallocate/);
	}
	my @subs = map {undef} @names;
	my $tmp = 0;
	my %mapping = map { $_ => $tmp++ } @names;
	my @otherargs = qw(debug threaded mountpoint mountopts nullpath_ok utimens_as_array nopath utime_omit_ok);
	my %otherargs = (
			  debug			=> 0,
			  threaded		=> 0,
			  mountpoint		=> "",
			  mountopts		=> "",
			  nullpath_ok		=> 0,
			  utimens_as_array	=> 0,
			  nopath		=> 0,
			  utime_omit_ok		=> 0,
			);
	while(my $name = shift) {
		my ($subref) = shift;
		if(exists($otherargs{$name})) {
			$otherargs{$name} = $subref;
		} else {
			croak "Usage: Fuse::main(getattr => \"main::my_getattr\", ...)" unless $subref;
			if (exists $mapping{$name}) {
				$subs[$mapping{$name}] = $subref;
			}
			else {
				carp "There is no function $name";
			}
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

sub fuse_buf_size {
	my ($buf) = @_;
	return sum(map { $_->{size} } @$buf);
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

=over 1

=item debug => boolean

This turns FUSE call tracing on and off.  Default is 0 (which means off).

=item mountpoint => string

The point at which to mount this filesystem.  There is no default, you must
specify this.  An example would be '/mnt'.

=item mountopts => string

This is a comma separated list of mount options to pass to the FUSE kernel
module.

At present, it allows the specification of the allow_other
argument when mounting the new FUSE filesystem. To use this, you will also
need 'user_allow_other' in /etc/fuse.conf as per the FUSE documention

  mountopts => "allow_other" or
  mountopts => ""

=item threaded => boolean

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

=item nullpath_ok => boolean

This flag tells Fuse to not pass paths for functions that operate on file
or directory handles. This will yield empty path parameters for functions
including read, write, flush, release, fsync, readdir, releasedir,
fsyncdir, truncate, fgetattr and lock. If you use this, you must return
file/directory handles from open, opendir and create. Default is 0 (off).
Only effective on Fuse 2.8 and up; with earlier versions, this does nothing.

=item utimens_as_array => boolean

This flag causes timestamps passed via the utimens() call to be passed
as arrays containing the time in seconds, and a second value containing
the number of nanoseconds, instead of a floating point value. This allows
for more precise times, as the normal floating point type used by Perl
(double) loses accuracy starting at about tenths of a microsecond.

=item nopath => boolean

Flag indicating that the path need not be calculated for the following
operations:

read, write, flush, release, fsync, readdir, releasedir, fsyncdir,
ftruncate, fgetattr, lock, ioctl and poll

Closely related to nullpath_ok, but if this flag is set then the path will
not be calculated even if the file wasn't unlinked. However the path can
still be defined if it needs to be calculated for some other reason.

Only effective on Fuse 2.9 and up.

=item utime_omit_ok => boolean

Flag indicating that the filesystem accepts special UTIME_NOW and
UTIME_OMIT values in its C<utimens> operation.

If you wish to use these constants, make sure to include the ':utime' flag
when including the Fuse module, or the ':all' flag.

Only effective on Fuse 2.9 and up.

=back

=head3 Fuse::fuse_get_context
 
 use Fuse "fuse_get_context";
 my $caller_uid = fuse_get_context()->{"uid"};
 my $caller_gid = fuse_get_context()->{"gid"};
 my $caller_pid = fuse_get_context()->{"pid"};
 
Access context information about the current Fuse operation. 

=head3 Fuse::fuse_version

Indicates the Fuse version in use; more accurately, indicates the version
of the Fuse API in use at build time. If called in scalar context, the
version will be returned as a decimal value; i.e., for Fuse API v2.6, will
return "2.6". If called in array context, an array will be returned,
containing the major, minor and micro version numbers of the Fuse API
it was built against.

=head3 Fuse::fuse_buf_size

Computes the total size of a buffer vector. Applicable for C<read_buf>
and C<write_buf> operations.

=head3 Fuse::fuse_buf_copy

Copies data from one buffer vector to another. Primarily useful if a
buffer vector contains multiple, fragmented chunks or if it contains an
FD buffer instead of a memory buffer. Applicable for C<write_buf>.

=head3 Fuse::notify_poll

Only available if the Fuse module is built against libfuse 2.8 or later.
Use fuse_version() to determine if this is the case. Calling this function
with a pollhandle argument (as provided to the C<poll> operation
implementation) will send a notification to the caller poll()ing for
I/O operation availability. If more than one pollhandle is provided for
the same filehandle, only use the latest; you *can* send notifications
to them all, but it is unnecessary and decreases performance.

ONLY supply poll handles fed to you through C<poll> to this function.
Due to thread safety requirements, we can't currently package the pointer
up in an object the way we'd like to to prevent this situation, but your
filesystem server program may segfault, or worse, if you feed things to
this function which it is not supposed to receive. If you do anyway, we
take no responsibility for whatever Bad Things(tm) may happen.

=head3 Fuse::pollhandle_destroy

Only available if the Fuse module is built against libfuse 2.8 or later.
Use fuse_version() to determine if this is the case. This function destroys
a poll handle (fed to your program through C<poll>). When you are done
with a poll handle, either because it has been replaced, or because a
notification has been sent to it, pass it to this function to dispose of
it safely.

ONLY supply poll handles fed to you through C<poll> to this function.
Due to thread safety requirements, we can't currently package the pointer
up in an object the way we'd like to to prevent this situation, but your
filesystem server program may segfault, or worse, if you feed things to
this function which it is not supposed to receive. If you do anyway, we
take no responsibility for whatever Bad Things(tm) may happen.

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

If you wish to provide sub-second precision timestamps, they may be
passed either as the fractional part of a floating-point value, or as a
two-element array, passed as an array ref, with the first element
containing the number of seconds since the epoch, and the second
containing the number of nanoseconds. This provides complete time
precision, as a floating point number starts losing precision at about
a tenth of a microsecond. So if you really care about that sort of thing...

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

No creation, or truncation flags (O_CREAT, O_EXCL, O_TRUNC) will be passed to open().
The fileinfo hash reference contains flags from the Fuse open call which may be modified by the module. The only fields presently supported are:
 direct_io (version 2.4 onwards)
 keep_cache (version 2.4 onwards)
 nonseekable (version 2.8 onwards)
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

Arguments: Pathname, numeric flags passed to open, file handle, flock_release flag (when built against FUSE 2.9 or later), lock owner ID (when built against FUSE 2.9 or later)

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

Removes the named extended attribute (if present) from a file.

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

Like utime(), but allows time resolution down to the nanosecond. By default,
times are passed as "numeric" (internally these are typically represented
as "double"), so the sub-second portion is represented as fractions of a
second. If you want times passed as arrays instead of floating point
values, for higher precision, you should pass the C<utimens_as_array> option
to C<Fuse::main>.

Note that if this call is implemented, it overrides utime() ALWAYS.

=head3 bmap

Arguments: Pathname, numeric blocksize, numeric block number

Returns errno or 0 on success, and physical block number if successful

Used to map a block number offset in a file to the physical block offset
on the block device backing the file system. This is intended for
filesystems that are stored on an actual block device, with the 'blkdev'
option passed.

=head3 ioctl

Arguments: Pathname, ioctl command code, flags, data if ioctl op is a write, (optional) file handle

Returns errno or 0 on success, and data if ioctl op is a read

Used to handle ioctl() operations on files. See ioctl(2) for more
information on the fine details of ioctl operation numbers. May need to
h2ph system headers to get the necessary macros; keep in mind the macros
are highly OS-dependent.

Keep in mind that read and write are from the client perspective, so
read from our end means data is going *out*, and write means data is
coming *in*. It can be slightly confusing.

=head3 poll

Arguments: Pathname, poll handle ID (or undef if none), event mask, (optional) file handle

Returns errno or 0 on success, and updated event mask on success

Used to handle poll() operations on files. See poll(2) to learn more about
event polling. Use IO::Poll to get the POLLIN, POLLOUT, and other symbols
to describe the events which can happen on the filehandle. Save the poll
handle ID to be passed to C<notify_poll> and C<pollhandle_destroy>
functions, if it is not undef. Threading will likely be necessary for this
operation to work.

There is not an "out of band" data transfer channel provided as part of
FUSE, so POLLPRI/POLLRDBAND/POLLWRBAND won't work.

Poll handle is currently a read-only scalar; we are investigating a way
to make this an object instead.

=head3 write_buf

Arguments: Pathname, offset, buffer vector, (optional) file handle.

Write contents of buffer to an open file.

Similar to the C<write> method, but data is supplied in a generic buffer.
Use fuse_buf_copy() to transfer data to the destination if necessary.

=head3 read_buf

Arguments: Pathname, size, offset, buffer vector, (optional) file handle.

Store data from an open file in a buffer.

Similar to the C<read> method, but data is stored and returned in a generic
buffer.

No actual copying of data has to take place, the source file descriptor
may simply be placed in the 'fd' member of the buffer access hash (and
the 'flags' member OR'd with FUSE_BUF_IS_FD) for later retrieval.

Also, if the FUSE_BUF_FD_SEEK constant is OR'd with 'flags', the 'pos'
member should contain the offset (in bytes) to seek to in the file
descriptor.

If data is to be read, the read data should be placed in the 'mem' member
of the buffer access hash, and the 'size' member should be updated if less
data was read than requested.

=head3 flock

Arguments: pathname, (optional) file handle, unique lock owner ID, operation ID

Perform BSD-style file locking operations.

Operation ID will be one of LOCK_SH, LOCK_EX or LOCK_UN. Non-blocking lock
requests will be indicated by having LOCK_NB OR'd into the value.

For more information, see the flock(2) manpage. For the lock symbols, do:

  use Fcntl qw(flock);

Locking is handled locally, but this allows (especially for networked file
systems) for protocol-level locking semantics to also be employed, if any
are available.

=head3 fallocate

Arguments: pathname, (optional) file handle, mode, offset, length

Allocates space for an open file.

This function ensures that required space is allocated for specified file.
If this function returns success then any subsequent write request to
specified range is guaranteed not to fail because of lack of space on
the file system media.

=head1 EXAMPLES

There are a few example scripts in the examples/ subdirectory.  These are:

example.pl

	A simple "Hello world" type of script

loopback.pl

	A filesystem loopback-device.  like fusexmp from the main FUSE dist,
	it simply recurses file operations into the real filesystem.  Unlike
	fusexmp, it only re-shares files under the /tmp/test directory.

rmount.pl

	An NFS-workalike which tunnels through SSH. It requires an account
	on some ssh server (obviously), with public-key authentication enabled.
	(if you have to type in a password, you don't have this. man ssh_keygen.).
	Copy rmount_remote.pl to your home directory on the remote machine
	and make it executable. Then create a mountpoint subdir somewhere local,
	and run the example script: ./rmount.pl host /remote/dir /local/dir

rmount_remote.pl

	A ripoff of loopback.pl meant to be used as a backend for rmount.pl.

=head1 AUTHOR

Mark Glines, E<lt>mark@glines.orgE<gt>

=head1 SEE ALSO

L<perl>, the FUSE documentation.

=cut
