#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <fuse.h>

/* Determine if threads support should be included */
#ifdef USE_ITHREADS
# ifdef I_PTHREAD
#  define FUSE_USE_ITHREADS
# else
#  error "Sorry, I don't know how to handle ithreads on this architecture."
# endif
#endif

/* Global Data */

#define MY_CXT_KEY "Fuse::_guts" XS_VERSION
#define N_CALLBACKS 25

typedef struct {
	SV *callback[N_CALLBACKS];
	tTHX self;
	int threaded;
	perl_mutex mutex;
} my_cxt_t;
START_MY_CXT;

#ifdef FUSE_USE_ITHREADS
tTHX master_interp = NULL;
# define FUSE_CONTEXT_PRE dTHX; if(!aTHX) {                   \
	dMY_CXT_INTERP(master_interp);                            \
	if(MY_CXT.threaded) {                                     \
		MUTEX_LOCK(&MY_CXT.mutex);                            \
		PERL_SET_CONTEXT(master_interp);                      \
		my_perl = perl_clone(MY_CXT.self, CLONEf_CLONE_HOST); \
		MUTEX_UNLOCK(&MY_CXT.mutex);                          \
	}                                                         \
} { dMY_CXT; dSP;
# define FUSE_CONTEXT_POST }
#else
# define FUSE_CONTEXT_PRE dTHX; dMY_CXT; dSP;
# define FUSE_CONTEXT_POST
#endif

#undef DEBUGf
#if 0
#define DEBUGf(f, a...) fprintf(stderr, "%s:%d (%i): " f,__BASE_FILE__,__LINE__,sp-PL_stack_base ,##a )
#else
#define DEBUGf(a...)
#endif

int _PLfuse_getattr(const char *file, struct stat *result) {
	int rv;
	FUSE_CONTEXT_PRE;
	DEBUGf("getattr begin: %s\n",file);
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,strlen(file))));
	PUTBACK;
	rv = call_sv(MY_CXT.callback[0],G_ARRAY);
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
		result->st_size = POPn;	// we pop double here to support files larger than 4Gb (long limit)
		result->st_rdev = POPi;
		result->st_gid = POPi;
		result->st_uid = POPi;
		result->st_nlink = POPi;
		result->st_mode = POPi;
		result->st_ino   = POPi;
		result->st_dev = POPi;
		rv = 0;
	}
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("getattr end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_readlink(const char *file,char *buf,size_t buflen) {
	int rv;
	if(buflen < 1)
		return EINVAL;
	FUSE_CONTEXT_PRE;
	DEBUGf("readlink begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	PUTBACK;
	rv = call_sv(MY_CXT.callback[1],G_SCALAR);
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
	DEBUGf("readlink end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

#if 0
/*
 * This doesn't yet work... we alwas get ENOSYS when trying to use readdir().
 * Well, of course, getdir() is fine as well.
 */
 int _PLfuse_readdir(const char *file, void *dirh, fuse_fill_dir_t dirfil, off_t off, struct fuse_file_info *fi) {
#endif
int _PLfuse_getdir(const char *file, fuse_dirh_t dirh, fuse_dirfil_t dirfil) {
	int prv, rv;
	FUSE_CONTEXT_PRE;
	DEBUGf("getdir begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	PUTBACK;
	prv = call_sv(MY_CXT.callback[2],G_ARRAY);
	SPAGAIN;
	if(prv) {
		rv = POPi;
		while(--prv)
			dirfil(dirh,POPp,0,0);
	} else {
		fprintf(stderr,"getdir() handler returned nothing!\n");
		rv = -ENOSYS;
	}
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("getdir end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_mknod (const char *file, mode_t mode, dev_t dev) {
	int rv;
	FUSE_CONTEXT_PRE;
	DEBUGf("mknod begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSViv(mode)));
	XPUSHs(sv_2mortal(newSViv(dev)));
	PUTBACK;
	rv = call_sv(MY_CXT.callback[3],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("mknod end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_mkdir (const char *file, mode_t mode) {
	int rv;
	FUSE_CONTEXT_PRE;
	DEBUGf("mkdir begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSViv(mode)));
	PUTBACK;
	rv = call_sv(MY_CXT.callback[4],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("mkdir end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}


int _PLfuse_unlink (const char *file) {
	int rv;
	FUSE_CONTEXT_PRE;
	DEBUGf("unlink begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	PUTBACK;
	rv = call_sv(MY_CXT.callback[5],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("unlink end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_rmdir (const char *file) {
	int rv;
	FUSE_CONTEXT_PRE;
	DEBUGf("rmdir begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	PUTBACK;
	rv = call_sv(MY_CXT.callback[6],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("rmdir end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_symlink (const char *file, const char *new) {
	int rv;
	FUSE_CONTEXT_PRE;
	DEBUGf("symlink begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSVpv(new,0)));
	PUTBACK;
	rv = call_sv(MY_CXT.callback[7],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("symlink end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_rename (const char *file, const char *new) {
	int rv;
	FUSE_CONTEXT_PRE;
	DEBUGf("rename begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSVpv(new,0)));
	PUTBACK;
	rv = call_sv(MY_CXT.callback[8],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("rename end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_link (const char *file, const char *new) {
	int rv;
	FUSE_CONTEXT_PRE;
	DEBUGf("link begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSVpv(new,0)));
	PUTBACK;
	rv = call_sv(MY_CXT.callback[9],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("link end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_chmod (const char *file, mode_t mode) {
	int rv;
	FUSE_CONTEXT_PRE;
	DEBUGf("chmod begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSViv(mode)));
	PUTBACK;
	rv = call_sv(MY_CXT.callback[10],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("chmod end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_chown (const char *file, uid_t uid, gid_t gid) {
	int rv;
	FUSE_CONTEXT_PRE;
	DEBUGf("chown begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSViv(uid)));
	XPUSHs(sv_2mortal(newSViv(gid)));
	PUTBACK;
	rv = call_sv(MY_CXT.callback[11],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("chown end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_truncate (const char *file, off_t off) {
	int rv;
#ifndef PERL_HAS_64BITINT
	char *temp;
#endif
	FUSE_CONTEXT_PRE;
	DEBUGf("truncate begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
#ifdef PERL_HAS_64BITINT
	XPUSHs(sv_2mortal(newSViv(off)));
#else
	asprintf(&temp, "%llu", off);
	XPUSHs(sv_2mortal(newSVpv(temp, 0)));
	free(temp);
#endif
	PUTBACK;
	rv = call_sv(MY_CXT.callback[12],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("truncate end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_utime (const char *file, struct utimbuf *uti) {
	int rv;
	FUSE_CONTEXT_PRE;
	DEBUGf("utime begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSViv(uti->actime)));
	XPUSHs(sv_2mortal(newSViv(uti->modtime)));
	PUTBACK;
	rv = call_sv(MY_CXT.callback[13],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("utime end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_open (const char *file, struct fuse_file_info *fi) {
	int rv;
	int flags = fi->flags;
	HV *fihash;
	FUSE_CONTEXT_PRE;
	DEBUGf("open begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSViv(flags)));
	/* Create a hashref containing the details from fi
	 * which we can look at or modify.
	 */
	fi->fh = 0; /* Ensure it starts with 0 - important if they don't set it */
	fihash = newHV();
#if FUSE_VERSION >= 24
	hv_store(fihash, "direct_io", 9, newSViv(fi->direct_io), 0);
	hv_store(fihash, "keep_cache", 10, newSViv(fi->keep_cache), 0);
#endif
#if FUSE_VERSION >= 29
	hv_store(fihash, "nonseekable", 11, newSViv(fi->nonseekable), 0);
#endif
	XPUSHs(sv_2mortal(newRV_noinc((SV*) fihash)));
	/* All hashref things done */

	PUTBACK;
	/* Open called with filename, flags */
	rv = call_sv(MY_CXT.callback[14],G_ARRAY);
	SPAGAIN;
	if(rv)
	{
		SV *sv;
		if (rv > 1)
		{
			sv = POPs;
			if (SvOK(sv))
			{
				/* We're holding on to the sv reference until
				 * after exit of this function, so we need to
				 * increment its reference count
				 */
				fi->fh = SvREFCNT_inc(sv);
			}
		}
		rv = POPi;
	}
	else
		rv = 0;
	if (rv == 0)
	{
		/* Success, so copy the file handle which they returned */
#if FUSE_VERSION >= 24
		SV **svp;
		svp = hv_fetch(fihash, "direct_io", 9, 0);
		if (svp != NULL)
		{
			fi->direct_io = SvIV(*svp);
		}
		svp = hv_fetch(fihash, "keep_cache", 10, 0);
		if (svp != NULL)
		{
			fi->keep_cache = SvIV(*svp);
		}
#endif
#if FUSE_VERSION >= 29
		svp = hv_fetch(fihash, "nonseekable", 11, 0);
		if (svp != NULL)
		{
			fi->nonseekable = SvIV(*svp);
		}
#endif
	}
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("open end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_read (const char *file, char *buf, size_t buflen, off_t off, struct fuse_file_info *fi) {
	int rv;
#ifndef PERL_HAS_64BITINT
	char *temp;
#endif
	FUSE_CONTEXT_PRE;
	DEBUGf("read begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSViv(buflen)));
#ifdef PERL_HAS_64BITINT
	XPUSHs(sv_2mortal(newSViv(off)));
#else
	asprintf(&temp, "%llu", off);
	XPUSHs(sv_2mortal(newSVpv(temp, 0)));
	free(temp);
#endif
	XPUSHs(fi->fh==0 ? &PL_sv_undef : (SV *)fi->fh);
	PUTBACK;
	rv = call_sv(MY_CXT.callback[15],G_SCALAR);
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
	DEBUGf("read end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_write (const char *file, const char *buf, size_t buflen, off_t off, struct fuse_file_info *fi) {
	int rv;
#ifndef PERL_HAS_64BITINT
	char *temp;
#endif
	FUSE_CONTEXT_PRE;
	DEBUGf("write begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSVpvn(buf,buflen)));
#ifdef PERL_HAS_64BITINT
	XPUSHs(sv_2mortal(newSViv(off)));
#else
	asprintf(&temp, "%llu", off);
	XPUSHs(sv_2mortal(newSVpv(temp, 0)));
	free(temp);
#endif
	XPUSHs(fi->fh==0 ? &PL_sv_undef : (SV *)fi->fh);
	PUTBACK;
	rv = call_sv(MY_CXT.callback[16],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("write end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_statfs (const char *file, struct statvfs *st) {
	int rv;
	FUSE_CONTEXT_PRE;
	DEBUGf("statfs begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	PUTBACK;
	rv = call_sv(MY_CXT.callback[17],G_ARRAY);
	SPAGAIN;
	DEBUGf("statfs got %i params\n",rv);
	if(rv == 6 || rv == 7) {
		st->f_bsize	= POPi;
		st->f_bfree	= POPi;
		st->f_blocks	= POPi;
		st->f_ffree	= POPi;
		st->f_files	= POPi;
		st->f_namemax	= POPi;
		/* zero and fill-in other */
		st->f_fsid = 0;
		st->f_frsize = 4096;
		st->f_flag = 0;
		st->f_bavail = st->f_bfree;
		st->f_favail = st->f_ffree;

		if(rv == 7)
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
	DEBUGf("statfs end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_flush (const char *file, struct fuse_file_info *fi) {
	int rv;
	FUSE_CONTEXT_PRE;
	DEBUGf("flush begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(fi->fh==0 ? &PL_sv_undef : (SV *)fi->fh);
	PUTBACK;
	rv = call_sv(MY_CXT.callback[18],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("flush end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_release (const char *file, struct fuse_file_info *fi) {
	int rv;
	int flags = fi->flags;
	FUSE_CONTEXT_PRE;
	DEBUGf("release begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSViv(flags)));
	XPUSHs(fi->fh==0 ? &PL_sv_undef : (SV *)fi->fh);
	PUTBACK;
	rv = call_sv(MY_CXT.callback[19],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	/* We're now finished with the handle that we were given, so
	 * we should decrement its count so that it can be freed.
	 */
	if (fi->fh != 0)
	{
		SvREFCNT_dec((SV *)fi->fh);
		fi->fh = 0;
	}
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("release end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_fsync (const char *file, int datasync, struct fuse_file_info *fi) {
	int rv;
	int flags = fi->flags;
	FUSE_CONTEXT_PRE;
	DEBUGf("fsync begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSViv(flags)));
	XPUSHs(fi->fh==0 ? &PL_sv_undef : (SV *)fi->fh);
	PUTBACK;
	rv = call_sv(MY_CXT.callback[20],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("fsync end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_setxattr (const char *file, const char *name, const char *buf, size_t buflen, int flags) {
	int rv;
	FUSE_CONTEXT_PRE;
	DEBUGf("setxattr begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSVpv(name,0)));
	XPUSHs(sv_2mortal(newSVpvn(buf,buflen)));
	XPUSHs(sv_2mortal(newSViv(flags)));
	PUTBACK;
	rv = call_sv(MY_CXT.callback[21],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("setxattr end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_getxattr (const char *file, const char *name, char *buf, size_t buflen) {
	int rv;
	FUSE_CONTEXT_PRE;
	DEBUGf("getxattr begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSVpv(name,0)));
	PUTBACK;
	rv = call_sv(MY_CXT.callback[22],G_SCALAR);
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
	DEBUGf("getxattr end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_listxattr (const char *file, char *list, size_t size) {
	int prv, rv;
	FUSE_CONTEXT_PRE;
	DEBUGf("listxattr begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	PUTBACK;
	prv = call_sv(MY_CXT.callback[23],G_ARRAY);
	SPAGAIN;
	if(!prv)
		rv = -ENOENT;
	else {

		char *p = list;
		int spc = size;
		int total_len = 0;

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
	DEBUGf("listxattr end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_removexattr (const char *file, const char *name) {
	int rv;
	FUSE_CONTEXT_PRE;
	DEBUGf("removexattr begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSVpv(name,0)));
	PUTBACK;
	rv = call_sv(MY_CXT.callback[24],G_SCALAR);
	SPAGAIN;
	if(rv)
		rv = POPi;
	else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("removexattr end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

struct fuse_operations _available_ops = {
getattr:		_PLfuse_getattr,
readlink:		_PLfuse_readlink,
getdir:			_PLfuse_getdir,
#if 0
readdir:		_PLfuse_readdir,
#endif
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

BOOT:
	MY_CXT_INIT;
	MY_CXT.self = aTHX;

void
CLONE(...)
	PREINIT:
		int i;
		dTHX;
	CODE:
		MY_CXT_CLONE;
		tTHX parent = MY_CXT.self;
		MY_CXT.self = my_perl;
#if (PERL_VERSION < 13) || (PERL_VERSION == 13 && PERL_SUBVERSION <= 1)
		CLONE_PARAMS clone_param;
		clone_param.flags = 0;
		for(i=0;i<N_CALLBACKS;i++) {
			if(MY_CXT.callback[i]) {
				MY_CXT.callback[i] = sv_dup(MY_CXT.callback[i], &clone_param);
			}
		}
#else
		CLONE_PARAMS *clone_param = clone_params_new(parent, aTHX);
		for(i=0;i<N_CALLBACKS;i++) {
			if(MY_CXT.callback[i]) {
				MY_CXT.callback[i] = sv_dup(MY_CXT.callback[i], clone_param);
			}
		}
		clone_params_del(clone_param);
#endif

SV*
fuse_get_context()
	PREINIT:
	struct fuse_context *fc;
	CODE:
	fc = fuse_get_context();
	if(fc) {
		HV *hash = newHV();
		hv_store(hash, "uid", 3, newSViv(fc->uid), 0);
		hv_store(hash, "gid", 3, newSViv(fc->gid), 0);
		hv_store(hash, "pid", 3, newSViv(fc->pid), 0);
		RETVAL = newRV_noinc((SV*)hash);
	} else {
		XSRETURN_UNDEF;
	}
	OUTPUT:
	RETVAL

void
perl_fuse_main(...)
	PREINIT:
	struct fuse_operations fops = 
		{NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
		 NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL};
	int i, debug;
	char *mountpoint;
	char *mountopts;
	struct fuse_args margs = FUSE_ARGS_INIT(0, NULL);
	struct fuse_args fargs = FUSE_ARGS_INIT(0, NULL);
	struct fuse_chan *fc;
	dMY_CXT;
	INIT:
	if(items != 29) {
		fprintf(stderr,"Perl<->C inconsistency or internal error\n");
		XSRETURN_UNDEF;
	}
	CODE:
	debug = SvIV(ST(0));
	MY_CXT.threaded = SvIV(ST(1));
	if(MY_CXT.threaded) {
#ifdef FUSE_USE_ITHREADS
		master_interp = aTHX;
		MUTEX_INIT(&MY_CXT.mutex);
#else
		fprintf(stderr,"FUSE warning: Your script has requested multithreaded "
		               "mode, but your perl was not built with -Dusethreads.  "
		               "Threads are disabled.\n");
		MY_CXT.threaded = 0;
#endif
	}
	mountpoint = SvPV_nolen(ST(2));
	mountopts = SvPV_nolen(ST(3));
	for(i=0;i<N_CALLBACKS;i++) {
		SV *var = ST(i+4);
		/* allow symbolic references, or real code references. */
		if(SvOK(var) && (SvPOK(var) || (SvROK(var) && SvTYPE(SvRV(var)) == SVt_PVCV))) {
			void **tmp1 = (void**)&_available_ops, **tmp2 = (void**)&fops;
			tmp2[i] = tmp1[i];
			MY_CXT.callback[i] = var;
		} else if(SvOK(var)) {
			croak("invalid callback (%i) passed to perl_fuse_main "
			      "(%s is not a string, code ref, or undef).\n",
			      i+4,SvPVbyte_nolen(var));
		} else {
			MY_CXT.callback[i] = NULL;
		}
	}
	/*
	 * XXX: What comes here is just a ridiculous use of the option parsing API
	 * to hack on compatibility with other parts of the new API. First and
	 * foremost, real C argc/argv would be good to get at...
	 */
	if (mountopts &&
	    (fuse_opt_add_arg(&margs, "") == -1 ||
	     fuse_opt_add_arg(&margs, "-o") == -1 ||
	     fuse_opt_add_arg(&margs, mountopts) == -1)) {
		fuse_opt_free_args(&margs);
		croak("out of memory\n");
	}
	fc = fuse_mount(mountpoint,&margs);
	fuse_opt_free_args(&margs);        
	if (fc == NULL)
		croak("could not mount fuse filesystem!\n");
        if (debug) {
		if ( fuse_opt_add_arg(&fargs, "") == -1 ||
			fuse_opt_add_arg(&fargs, "-d") == -1) {
			fuse_opt_free_args(&fargs);
			croak("out of memory\n");
		}
	} else {
		if (fuse_opt_add_arg(&fargs, "") == -1)
			croak("out of memory\n");
	}
#ifndef __NetBSD__
	if(MY_CXT.threaded) {
		fuse_loop_mt(fuse_new(fc,&fargs,&fops,sizeof(fops),NULL));
	} else
#endif
		fuse_loop(fuse_new(fc,&fargs,&fops,sizeof(fops),NULL));
	fuse_unmount(mountpoint,fc);
	fuse_opt_free_args(&fargs);
