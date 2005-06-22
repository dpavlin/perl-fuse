#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <fuse/fuse.h>

#undef DEBUGf
#if 0
#define DEBUGf(f, a...) fprintf(stderr, "%s:%d (%i): " f,__BASE_FILE__,__LINE__,PL_stack_sp-PL_stack_base ,##a )
#else
#define DEBUGf(a...)
#endif

#define N_CALLBACKS 25
SV *_PLfuse_callbacks[N_CALLBACKS];

int _PLfuse_getattr(const char *file, struct stat *result) {
	dSP;
	int rv, statcount;
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,strlen(file))));
	PUTBACK;
	rv = call_sv(_PLfuse_callbacks[0],G_ARRAY);
	SPAGAIN;
	if(rv != 13) {
		if(rv > 1) {
			fprintf(stderr,"inappropriate number of returned values from getattr\n");
			rv = -ENOSYS;
		} else if(rv)
			rv = POPi;
		else
			rv = -ENOENT;
	} else {
		result->st_blocks = POPi;
		result->st_blksize = POPi;
		result->st_ctime = POPi;
		result->st_mtime = POPi;
		result->st_atime = POPi;
		result->st_size = POPi;
		result->st_rdev = POPi;
		result->st_gid = POPi;
		result->st_uid = POPi;
		result->st_nlink = POPi;
		result->st_mode = POPi;
		/*result->st_ino =*/ POPi;
		result->st_dev = POPi;
		rv = 0;
	}
	FREETMPS;
	LEAVE;
	PUTBACK;
	return rv;
}

int _PLfuse_readlink(const char *file,char *buf,size_t buflen) {
	int rv;
	char *rvstr;
	dSP;
	I32 ax;
	if(buflen < 1)
		return EINVAL;
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	PUTBACK;
	rv = call_sv(_PLfuse_callbacks[1],G_SCALAR);
	SPAGAIN;
	if(!rv)
		rv = -ENOENT;
	else {
		SV *mysv = POPs;
		if(SvTYPE(mysv) == SVt_IV || SvTYPE(mysv) == SVt_NV)
			rv = SvIV(mysv);
		else {
			strncpy(buf,SvPV_nolen(mysv),buflen);
			rv = 0;
		}
	}
	FREETMPS;
	LEAVE;
	buf[buflen-1] = 0;
	PUTBACK;
	return rv;
}

int _PLfuse_getdir(const char *file, fuse_dirh_t dirh, fuse_dirfil_t dirfil) {
	int prv, rv;
	dSP;
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	PUTBACK;
	prv = call_sv(_PLfuse_callbacks[2],G_ARRAY);
	SPAGAIN;
	if(prv) {
		rv = POPi;
		while(--prv)
			dirfil(dirh,POPp,0);
	} else {
		fprintf(stderr,"getdir() handler returned nothing!\n");
		rv = -ENOSYS;
	}
	FREETMPS;
	LEAVE;
	PUTBACK;
	return rv;
}

int _PLfuse_mknod (const char *file, mode_t mode, dev_t dev) {
	int rv;
	SV *rvsv;
	char *rvstr;
	dSP;
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSViv(mode)));
	XPUSHs(sv_2mortal(newSViv(dev)));
	PUTBACK;
	rv = call_sv(_PLfuse_callbacks[3],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	return rv;
}

int _PLfuse_mkdir (const char *file, mode_t mode) {
	int rv;
	SV *rvsv;
	char *rvstr;
	dSP;
	DEBUGf("mkdir begin: %i\n",sp-PL_stack_base);
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSViv(mode)));
	PUTBACK;
	rv = call_sv(_PLfuse_callbacks[4],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("mkdir end: %i %i\n",sp-PL_stack_base,rv);
	return rv;
}


int _PLfuse_unlink (const char *file) {
	int rv;
	SV *rvsv;
	char *rvstr;
	dSP;
	DEBUGf("unlink begin: %i\n",sp-PL_stack_base);
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	PUTBACK;
	rv = call_sv(_PLfuse_callbacks[5],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("unlink end: %i\n",sp-PL_stack_base);
	return rv;
}

int _PLfuse_rmdir (const char *file) {
	int rv;
	SV *rvsv;
	char *rvstr;
	dSP;
	DEBUGf("rmdir begin: %i\n",sp-PL_stack_base);
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	PUTBACK;
	rv = call_sv(_PLfuse_callbacks[6],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("rmdir end: %i %i\n",sp-PL_stack_base,rv);
	return rv;
}

int _PLfuse_symlink (const char *file, const char *new) {
	int rv;
	SV *rvsv;
	char *rvstr;
	dSP;
	DEBUGf("symlink begin: %i\n",sp-PL_stack_base);
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSVpv(new,0)));
	PUTBACK;
	rv = call_sv(_PLfuse_callbacks[7],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("symlink end: %i\n",sp-PL_stack_base);
	return rv;
}

int _PLfuse_rename (const char *file, const char *new) {
	int rv;
	SV *rvsv;
	char *rvstr;
	dSP;
	DEBUGf("rename begin: %i\n",sp-PL_stack_base);
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSVpv(new,0)));
	PUTBACK;
	rv = call_sv(_PLfuse_callbacks[8],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("rename end: %i\n",sp-PL_stack_base);
	return rv;
}

int _PLfuse_link (const char *file, const char *new) {
	int rv;
	SV *rvsv;
	char *rvstr;
	dSP;
	DEBUGf("link begin: %i\n",sp-PL_stack_base);
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSVpv(new,0)));
	PUTBACK;
	rv = call_sv(_PLfuse_callbacks[9],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("link end: %i\n",sp-PL_stack_base);
	return rv;
}

int _PLfuse_chmod (const char *file, mode_t mode) {
	int rv;
	SV *rvsv;
	char *rvstr;
	dSP;
	DEBUGf("chmod begin: %i\n",sp-PL_stack_base);
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSViv(mode)));
	PUTBACK;
	rv = call_sv(_PLfuse_callbacks[10],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("chmod end: %i\n",sp-PL_stack_base);
	return rv;
}

int _PLfuse_chown (const char *file, uid_t uid, gid_t gid) {
	int rv;
	SV *rvsv;
	char *rvstr;
	dSP;
	DEBUGf("chown begin: %i\n",sp-PL_stack_base);
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSViv(uid)));
	XPUSHs(sv_2mortal(newSViv(gid)));
	PUTBACK;
	rv = call_sv(_PLfuse_callbacks[11],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("chown end: %i\n",sp-PL_stack_base);
	return rv;
}

int _PLfuse_truncate (const char *file, off_t off) {
	int rv;
	SV *rvsv;
	char *rvstr;
	dSP;
	DEBUGf("truncate begin: %i\n",sp-PL_stack_base);
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSViv(off)));
	PUTBACK;
	rv = call_sv(_PLfuse_callbacks[12],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("truncate end: %i\n",sp-PL_stack_base);
	return rv;
}

int _PLfuse_utime (const char *file, struct utimbuf *uti) {
	int rv;
	SV *rvsv;
	char *rvstr;
	dSP;
	DEBUGf("utime begin: %i\n",sp-PL_stack_base);
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSViv(uti->actime)));
	XPUSHs(sv_2mortal(newSViv(uti->modtime)));
	PUTBACK;
	rv = call_sv(_PLfuse_callbacks[13],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("utime end: %i\n",sp-PL_stack_base);
	return rv;
}

int _PLfuse_open (const char *file, int flags) {
	int rv;
	SV *rvsv;
	char *rvstr;
	dSP;
	DEBUGf("open begin: %i\n",sp-PL_stack_base);
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSViv(flags)));
	PUTBACK;
	rv = call_sv(_PLfuse_callbacks[14],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("open end: %i %i\n",sp-PL_stack_base,rv);
	return rv;
}

int _PLfuse_read (const char *file, char *buf, size_t buflen, off_t off) {
	int rv;
	char *rvstr;
	dSP;
	DEBUGf("read begin: %i\n",sp-PL_stack_base);
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSViv(buflen)));
	XPUSHs(sv_2mortal(newSViv(off)));
	PUTBACK;
	rv = call_sv(_PLfuse_callbacks[15],G_SCALAR);
	SPAGAIN;
	if(!rv)
		rv = -ENOENT;
	else {
		SV *mysv = POPs;
		if(SvTYPE(mysv) == SVt_NV || SvTYPE(mysv) == SVt_IV)
			rv = SvIV(mysv);
		else {
			if(SvPOK(mysv)) {
				rv = SvCUR(mysv);
			} else {
				rv = 0;
			}
			if(rv > buflen)
				croak("read() handler returned more than buflen! (%i > %i)",rv,buflen);
			if(rv)
				memcpy(buf,SvPV_nolen(mysv),rv);
		}
	}
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("read end: %i %i\n",sp-PL_stack_base,rv);
	return rv;
}

int _PLfuse_write (const char *file, const char *buf, size_t buflen, off_t off) {
	int rv;
	char *rvstr;
	dSP;
	DEBUGf("write begin: %i\n",sp-PL_stack_base);
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSVpvn(buf,buflen)));
	XPUSHs(sv_2mortal(newSViv(off)));
	PUTBACK;
	rv = call_sv(_PLfuse_callbacks[16],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("write end: %i\n",sp-PL_stack_base);
	return rv;
}

int _PLfuse_statfs (const char *file, struct statfs *st) {
	int rv;
	char *rvstr;
	dSP;
	DEBUGf("statfs begin: %i\n",sp-PL_stack_base);
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	PUTBACK;
	rv = call_sv(_PLfuse_callbacks[17],G_ARRAY);
	SPAGAIN;
	if(rv > 5) {
		st->f_bsize    = POPi;
		st->f_bfree    = POPi;
		st->f_blocks   = POPi;
		st->f_ffree    = POPi;
		st->f_files    = POPi;
		st->f_namelen  = POPi;
		if(rv > 6)
			rv = POPi;
		else
			rv = 0;
	} else
	if(rv > 1)
		croak("inappropriate number of returned values from statfs");
	else
	if(rv)
		rv = POPi;
	else
		rv = -ENOSYS;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("statfs end: %i\n",sp-PL_stack_base);
	return rv;
}

int _PLfuse_flush (const char *file) {
	int rv;
	char *rvstr;
	dSP;
	DEBUGf("flush begin: %i\n",sp-PL_stack_base);
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	PUTBACK;
	rv = call_sv(_PLfuse_callbacks[18],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("flush end: %i\n",sp-PL_stack_base);
	return rv;
}

int _PLfuse_release (const char *file, int flags) {
	int rv;
	char *rvstr;
	dSP;
	DEBUGf("release begin: %i\n",sp-PL_stack_base);
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSViv(flags)));
	PUTBACK;
	rv = call_sv(_PLfuse_callbacks[19],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("release end: %i\n",sp-PL_stack_base);
	return rv;
}

int _PLfuse_fsync (const char *file, int flags) {
	int rv;
	char *rvstr;
	dSP;
	DEBUGf("fsync begin: %i\n",sp-PL_stack_base);
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSViv(flags)));
	PUTBACK;
	rv = call_sv(_PLfuse_callbacks[20],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("fsync end: %i\n",sp-PL_stack_base);
	return rv;
}

int _PLfuse_setxattr (const char *file, const char *name, const char *buf, size_t buflen, int flags) {
	int rv;
	char *rvstr;
	dSP;
	DEBUGf("setxattr begin: %i\n",sp-PL_stack_base);
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSVpv(name,0)));
	XPUSHs(sv_2mortal(newSVpvn(buf,buflen)));
	XPUSHs(sv_2mortal(newSViv(flags)));
	PUTBACK;
	rv = call_sv(_PLfuse_callbacks[21],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("setxattr end: %i\n",sp-PL_stack_base);
	return rv;
}

int _PLfuse_getxattr (const char *file, const char *name, char *buf, size_t buflen) {
	int rv;
	char *rvstr;
	dSP;
	DEBUGf("getxattr begin: %i\n",sp-PL_stack_base);
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSVpv(name,0)));
	PUTBACK;
	rv = call_sv(_PLfuse_callbacks[22],G_SCALAR);
	SPAGAIN;
	if(!rv)
		rv = -ENOENT;
	else {
		SV *mysv = POPs;

		rv = 0;
		if(SvTYPE(mysv) == SVt_NV || SvTYPE(mysv) == SVt_IV)
			rv = SvIV(mysv);
		else {
			if(SvPOK(mysv)) {
				rv = SvCUR(mysv);
			} else {
				rv = 0;
			}
			if ((rv > 0) && (buflen > 0))
			{
				if(rv > buflen)
					rv = -ERANGE;
				else
					memcpy(buf,SvPV_nolen(mysv),rv);
			}
		}
	}
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("getxattr end: %i\n",sp-PL_stack_base);
	return rv;
}

int _PLfuse_listxattr (const char *file, char *list, size_t size) {
	int prv, rv;
	char *rvstr;
	dSP;
	DEBUGf("listxattr begin: %i\n",sp-PL_stack_base);
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	PUTBACK;
	prv = call_sv(_PLfuse_callbacks[23],G_ARRAY);
	SPAGAIN;
	if(!prv)
		rv = -ENOENT;
	else {

		char *p = list;
		int spc = size;
		int total_len = 0;
		int i;

		rv = POPi;
		prv--;

		/* Always nul terminate */
		if (list && (size > 0))
			list[0] = '\0';

		while (prv > 0)
		{
			SV *mysv = POPs;
			prv--;

			if (SvPOK(mysv)) {
				/* Copy nul too */
				int s = SvCUR(mysv) + 1;
				total_len += s;

				if (p && (size > 0) && (spc >= s))
				{
					memcpy(p,SvPV_nolen(mysv),s);
					p += s;
					spc -= s;
				}
			}
		}

		/*
		 * If the Perl returned an error, return that.
		 * Otherwise check that the buffer was big enough.
		 */
		if (rv == 0)
		{
			rv = total_len;
			if ((size > 0) && (size < total_len))
				rv = -ERANGE;
		}
	}
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("listxattr end: %i\n",sp-PL_stack_base);
	return rv;
}

int _PLfuse_removexattr (const char *file, const char *name) {
	int rv;
	char *rvstr;
	dSP;
	DEBUGf("removexattr begin: %i\n",sp-PL_stack_base);
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSVpv(name,0)));
	PUTBACK;
	rv = call_sv(_PLfuse_callbacks[24],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("removexattr end: %i\n",sp-PL_stack_base);
	return rv;
}

struct fuse_operations _available_ops = {
getattr:		_PLfuse_getattr,
readlink:		_PLfuse_readlink,
getdir:			_PLfuse_getdir,
mknod:			_PLfuse_mknod,
mkdir:			_PLfuse_mkdir,
unlink:			_PLfuse_unlink,
rmdir:			_PLfuse_rmdir,
symlink:		_PLfuse_symlink,
rename:			_PLfuse_rename,
link:			_PLfuse_link,
chmod:			_PLfuse_chmod,
chown:			_PLfuse_chown,
truncate:		_PLfuse_truncate,
utime:			_PLfuse_utime,
open:			_PLfuse_open,
read:			_PLfuse_read,
write:			_PLfuse_write,
statfs:			_PLfuse_statfs,
flush:			_PLfuse_flush,
release:		_PLfuse_release,
fsync:			_PLfuse_fsync,
setxattr:		_PLfuse_setxattr,
getxattr:		_PLfuse_getxattr,
listxattr:		_PLfuse_listxattr,
removexattr:		_PLfuse_removexattr,
};

MODULE = Fuse		PACKAGE = Fuse
PROTOTYPES: DISABLE

void
perl_fuse_main(...)
	PREINIT:
	struct fuse_operations fops = {NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL};
	int i, fd, varnum = 0, debug, have_mnt;
	char *mountpoint;
	char *mountopts;
	STRLEN n_a;
	STRLEN l;
	INIT:
	if(items != 28) {
		fprintf(stderr,"Perl<->C inconsistency or internal error\n");
		XSRETURN_UNDEF;
	}
	CODE:
	debug = SvIV(ST(0));
	mountpoint = SvPV_nolen(ST(1));
	mountopts = SvPV_nolen(ST(2));
	/* FIXME: reevaluate multithreading support when perl6 arrives */
	for(i=0;i<N_CALLBACKS;i++) {
		SV *var = ST(i+3);
		if((var != &PL_sv_undef) && SvROK(var)) {
			if(SvTYPE(SvRV(var)) == SVt_PVCV) {
				void **tmp1 = (void**)&_available_ops, **tmp2 = (void**)&fops;
				tmp2[i] = tmp1[i];
				_PLfuse_callbacks[i] = var;
			} else
				croak("arg is not a code reference!");
		}
	}
	/* FIXME: need to pass fusermount arguments */
	fd = fuse_mount(mountpoint,mountopts);
	if(fd < 0)
		croak("could not mount fuse filesystem!");
	fuse_loop(fuse_new(fd,debug ? "debug" : NULL,&fops));
