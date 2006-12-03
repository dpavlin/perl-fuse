#!/usr/bin/perl
use test::helper qw($_real $_point);
use Test::More;
plan tests => 24;
use English;

my (@stat);

chdir($_point);
ok(!(system("touch reg"      )>>8),"create normal file");
ok(!(system("mknod fifo p"   )>>8),"create fifo");

chdir($_real);
ok(-e "reg" ,"normal file exists");
ok(-e "fifo","fifo exists");
ok(-f "reg" ,"normal file is normal file");
ok(-p "fifo","fifo is fifo");

SKIP: {
	skip('Need root to mknod devices', 8) unless ($UID == 0);

	chdir($_point);
	ok(!(system("mknod chr c 2 3")>>8),"create chrdev");
	ok(!(system("mknod blk b 2 3")>>8),"create blkdev");

	chdir($_real);
	ok(-e "chr" ,"chrdev exists");
	ok(-e "blk" ,"blkdev exists");
        
        skip('mknod() is just pretend under fakeroot(1)', 4)
          if exists $ENV{FAKEROOTKEY};

	ok(-c "chr" ,"chrdev is chrdev");
	ok(-b "blk" ,"blkdev is blkdev");

	@stat = stat("chr");
	is($stat[6],3+(2<<8),"chrdev has right major,minor");
	@stat = stat("blk");
	is($stat[6],3+(2<<8),"blkdev has right major,minor");
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
	is($stat[6],3+(2<<8),"chrdev has right major,minor");
	@stat = stat("blk");
	is($stat[6],3+(2<<8),"blkdev has right major,minor");
}

map { unlink } qw(reg chr blk fifo);
