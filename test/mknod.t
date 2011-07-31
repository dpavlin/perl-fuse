#!/usr/bin/perl
use test::helper qw($_real $_point);
use Test::More;
plan tests => 24;
use English;
use Unix::Mknod qw(:all);
use Fcntl qw(:mode);
use POSIX;

my (@stat);

chdir($_point);
ok(!(system("touch reg"      )>>8),"create normal file");
ok(defined mkfifo($_point.'/fifo', 0600),"create fifo");

chdir($_real);
ok(-e "reg" ,"normal file exists");
ok(-e "fifo","fifo exists");
ok(-f "reg" ,"normal file is normal file");
ok(-p "fifo","fifo is fifo");

SKIP: {
	skip('Need root to mknod devices', 8) unless ($UID == 0);

	chdir($_point);
	ok(!mknod($_point.'/chr', 0600|S_IFCHR, makedev(2,3)),"create chrdev");
	ok(!mknod($_point.'/blk', 0600|S_IFBLK, makedev(2,3)),"create blkdev");

	chdir($_real);
	ok(-e "chr" ,"chrdev exists");
	ok(-e "blk" ,"blkdev exists");
        
        skip('mknod() is just pretend under fakeroot(1)', 4)
          if exists $ENV{FAKEROOTKEY};

	ok(-c "chr" ,"chrdev is chrdev");
	ok(-b "blk" ,"blkdev is blkdev");

	@stat = stat("chr");
	is($stat[6],makedev(2,3),"chrdev has right major,minor");
	@stat = stat("blk");
	is($stat[6],makedev(2,3),"blkdev has right major,minor");
}

chdir($_point);
ok(-e "reg" ,"normal file exists");
ok(-e "fifo","fifo exists");
ok(-f "reg" ,"normal file is normal file");
ok(-p "fifo","fifo is fifo");

SKIP: {
	skip('Need root to mknod devices', 6) unless ($UID == 0);

	ok(-e "chr" ,"chrdev exists");
	ok(-e "blk" ,"blkdev exists");
	ok(-c "chr" ,"chrdev is chrdev");
	ok(-b "blk" ,"blkdev is blkdev");

	@stat = stat("chr");
	is($stat[6],makedev(2,3),"chrdev has right major,minor");
	@stat = stat("blk");
	is($stat[6],makedev(2,3),"blkdev has right major,minor");
}

map { unlink } qw(reg chr blk fifo);
