#!/usr/bin/perl
use test::helper qw($_real $_point);
use Test::More;
use Config;

my $has_Filesys__Statvfs = 0;
eval {
    require Filesys::Statvfs;
    1;
} and do {
    $has_Filesys__Statvfs = 1;
    Filesys::Statvfs->import();
};

my $has_syscall = 0;
eval {
   require 'sys/syscall.ph'; # for SYS_statfs
   1;
} and do {
    $has_syscall = 1;
};

if (!($has_syscall || $has_Filesys__Statvfs)) {
    plan skip_all => 'No Filesys::Statvfs and no sys/syscall.ph';
}

# Maybe not the best way to do this... but it works. Only extract the values
# we care about, so we don't have to worry about changing field ordering
# around and other such nastiness.
my $packmask;
# Don't even bother setting up a packmask if we have Filesys::Statvfs.
# In that case, we can just make one call, and save ourselves a ton of
# messing around.
if (!$has_Filesys__Statvfs) {
    if ($^O eq 'linux') {
        $packmask = 'x[L!]L![6]x[L]x[L]L';
    }
    elsif ($^O eq 'freebsd') {
        $packmask = 'x[16]Qx[8]Q[2]qQqx[112]Lx[4]';
    }
    elsif ($^O eq 'netbsd') {
        if ($Config{'use64bitint'}) {
            # This should work for any 64-bit NetBSD...
            $packmask = 'x[8]Lx![q]x[16]Q[3]x[8]Q[2]x[64]L';
        }
        else {
            # NetBSD's perl on 32-bit doesn't handle quadword types, and
            # this is my workaround. Ugly, but it does the job. And yes,
            # won't work for big values. Good thing we're not testing
            # with any, huh?
            if ($Config{'byteorder'} eq '1234') { # little endian
                $packmask = 'x[4]Lx[8]Lx[4]Lx[4]Lx[4]x[8]Lx[4]Lx[4]x[64]L';
            }
            elsif ($Config{'byteorder'} eq '4321') { # big endian
                $packmask = 'x[4]Lx[8]x[4]Lx[4]Lx[4]Lx[8]x[4]Lx[4]Lx[64]L';
            }
            else {
                plan skip_all => "Word ordering not known, don't know how to handle statvfs1()";
                exit(1);
            }
        }
    }
    elsif ($^O eq 'darwin') {
        # Accurate for OS X 10.6; 10.5 and earlier may not actually correspond
        # to this, if my understanding of statfs(2) on OS X is fair.
        $packmask = 'x[L!]L!x[L!]L![5]';
    }
    else {
        plan skip_all => 'Platform not known, need to know how to statfs';
        exit(1);
    }
}

if ($^O eq 'netbsd' || $^O eq 'darwin') {
    # Ignoring the f_namelen field; no such animal on OS X statfs(), and
	# NetBSD's statvfs1(2) syscall doesn't seem to handle f_namelen right
	# for PUFFS-based filesystems. Not our failure, and mostly irrelevant.
    plan tests => 6;
}
else {
    plan tests => 7;
}
my @list;
if ($has_Filesys__Statvfs) {
    # This is a neater way to do this - if it's available...
    ok(@list = (statvfs($_point))[1,2,3,4,5,6,9]);
}
elsif ($has_syscall) {
    # Just make the buffer large enough that we don't have to care...
    my ($statfs_data) = "\0" x 4096;
    my ($tmp) = $_point;
    if ($^O eq 'netbsd') {
        # NetBSD doesn't have statfs(2); statvfs1(2) is its closest analogue.
    	ok(!syscall(&SYS_statvfs1,$tmp,$statfs_data,1),'statvfs1');
    }
    else {
    	ok(!syscall(&SYS_statfs,$tmp,$statfs_data),'statfs');
    }
    @list = unpack($packmask,$statfs_data);
}
diag "statfs: ",join(', ', @list);
is(shift(@list),4096,'block size');
is(shift(@list),1000000,'blocks');
is(shift(@list),500000,'blocks free');
shift(@list);
is(shift(@list),1000000,'files');
is(shift(@list),500000,'files free');
unless ($^O eq 'netbsd' || $^O eq 'darwin') {
    is(shift(@list),255,'namelen');
}
