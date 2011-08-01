#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <fuse.h>

#if defined(__FreeBSD__) || defined(__NetBSD__)
# define XATTR_CREATE 1
# define XATTR_REPLACE 2
#else
# include <sys/xattr.h>
#endif

/* Determine if threads support should be included */
#ifdef USE_ITHREADS
# ifdef I_PTHREAD
#  define FUSE_USE_ITHREADS
#  if (PERL_VERSION < 8) || (PERL_VERSION == 8 && PERL_SUBVERSION < 9)
#    define tTHX PerlInterpreter*
#    define STR_WITH_LEN(s)  ("" s ""), (sizeof(s)-1)
#    define hv_fetchs(hv,key,lval) Perl_hv_fetch(aTHX_ hv, STR_WITH_LEN(key), lval)
#    define dMY_CXT_INTERP(interp) \
	SV *my_cxt_sv = *hv_fetchs(interp->Imodglobal, MY_CXT_KEY, TRUE); \
	my_cxt_t *my_cxtp = INT2PTR(my_cxt_t*, SvUV(my_cxt_sv))
#  endif
# else
#  warning "Sorry, I don't know how to handle ithreads on this architecture. Building non-threaded version"
# endif
#endif

/* Global Data */

#define MY_CXT_KEY "Fuse::_guts" XS_VERSION
#if FUSE_VERSION >= 28
# define N_CALLBACKS 40
/* # define N_CALLBACKS 41 */
#elif FUSE_VERSION >= 26
# define N_CALLBACKS 38
#elif FUSE_VERSION >= 25
# define N_CALLBACKS 35
#elif FUSE_VERSION >= 23
# define N_CALLBACKS 31
#else
# define N_CALLBACKS 25
#endif

typedef struct {
	SV *callback[N_CALLBACKS];
	HV *handles;
#ifdef USE_ITHREADS
	tTHX self;
#endif
	int threaded;
#ifdef USE_ITHREADS
	perl_mutex mutex;
#endif
} my_cxt_t;
START_MY_CXT;

#ifdef FUSE_USE_ITHREADS
tTHX master_interp = NULL;

#define CLONE_INTERP(parent) S_clone_interp(parent)
tTHX S_clone_interp(tTHX parent) {
#  if (PERL_VERSION < 10)
	tTHX my_perl = parent;
#endif
	dMY_CXT_INTERP(parent);
	if(MY_CXT.threaded) {
		MUTEX_LOCK(&MY_CXT.mutex);
		PERL_SET_CONTEXT(parent);
		dTHX;
#if (PERL_VERSION > 10) || (PERL_VERSION == 10 && PERL_SUBVERSION >= 1)
		tTHX child = perl_clone(parent, CLONEf_CLONE_HOST);
#else
		tTHX child = perl_clone(parent, CLONEf_CLONE_HOST | CLONEf_KEEP_PTR_TABLE);
		ptr_table_free(PL_ptr_table);
		PL_ptr_table = NULL;
#endif
		MUTEX_UNLOCK(&MY_CXT.mutex);
		return child;
	}
	return NULL;
}

# define FUSE_CONTEXT_PRE dTHX; if(!aTHX) aTHX = CLONE_INTERP(master_interp); { dMY_CXT; dSP;
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

#define FH_KEY(fi) sv_2mortal(newSViv((fi)->fh))
#define FH_GETHANDLE(fi) S_fh_get_handle(aTHX_ aMY_CXT_ fi)
#define FH_STOREHANDLE(fi,sv) S_fh_store_handle(aTHX_ aMY_CXT_ fi, sv)
#define FH_RELEASEHANDLE(fi) S_fh_release_handle(aTHX_ aMY_CXT_ fi)

SV *S_fh_get_handle(pTHX_ pMY_CXT_ struct fuse_file_info *fi) {
	SV *val;
	val = &PL_sv_undef;
	if(fi->fh != 0) {
		HE *he;
		if((he = hv_fetch_ent(MY_CXT.handles, FH_KEY(fi), 0, 0))) {
			val = HeVAL(he);
			SvGETMAGIC(val);
		}
	}
	return val;
}

void S_fh_release_handle(pTHX_ pMY_CXT_ struct fuse_file_info *fi) {
	if(fi->fh != 0) {
		(void)hv_delete_ent(MY_CXT.handles, FH_KEY(fi), G_DISCARD, 0);
		fi->fh = 0;
	}
}

void S_fh_store_handle(pTHX_ pMY_CXT_ struct fuse_file_info *fi, SV *sv) {
	if(SvOK(sv)) {
#ifdef FUSE_USE_ITHREADS
		if(MY_CXT.threaded) {
			SvSHARE(sv);
		}
#endif
		MAGIC *mg = (SvTYPE(sv) == SVt_PVMG) ? mg_find(sv, PERL_MAGIC_shared_scalar) : NULL;
		fi->fh = mg ? PTR2IV(mg->mg_ptr) : PTR2IV(sv);
		if(hv_store_ent(MY_CXT.handles, FH_KEY(fi), SvREFCNT_inc(sv), 0) == NULL) {
			SvREFCNT_dec(sv);
		}
		SvSETMAGIC(sv);
	}
}

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

int _PLfuse_getdir(const char *file, fuse_dirh_t dirh, fuse_dirfil_t dirfil) {
	int prv, rv;
	SV **swp;
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
		/* Should yield the bottom of the current stack... */
		swp = &TOPs - prv + 1;
		rv = POPi;
		/* Sort of a hack to walk the stack in order, instead of reverse
		 * order - trying to explain to potential users why they need to
		 * reverse the order of this array would be confusing, at best. */
		while (swp <= &TOPs)
			dirfil(dirh,SvPVx_nolen(*(swp++)),0,0);
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
	rv = (rv ? POPi : 0);
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
	rv = (rv ? POPi : 0);
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
	rv = (rv ? POPi : 0);
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
	rv = (rv ? POPi : 0);
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
	rv = (rv ? POPi : 0);
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
	rv = (rv ? POPi : 0);
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
	rv = (rv ? POPi : 0);
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
	rv = (rv ? POPi : 0);
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
	rv = (rv ? POPi : 0);
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
	if (asprintf(&temp, "%llu", off) == -1)
		croak("Memory allocation failure!");
	XPUSHs(sv_2mortal(newSVpv(temp, 0)));
	free(temp);
#endif
	PUTBACK;
	rv = call_sv(MY_CXT.callback[12],G_SCALAR);
	SPAGAIN;
	rv = (rv ? POPi : 0);
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
	rv = (rv ? POPi : 0);
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
	(void) hv_store(fihash, "direct_io",    9, newSViv(fi->direct_io),   0);
	(void) hv_store(fihash, "keep_cache",  10, newSViv(fi->keep_cache),  0);
#endif
#if FUSE_VERSION >= 29
	(void) hv_store(fihash, "nonseekable", 11, newSViv(fi->nonseekable), 0);
#endif
	XPUSHs(sv_2mortal(newRV_noinc((SV*) fihash)));
	/* All hashref things done */

	PUTBACK;
	/* Open called with filename, flags */
	rv = call_sv(MY_CXT.callback[14],G_ARRAY);
	SPAGAIN;
	if(rv) {
		if(rv > 1) {
			FH_STOREHANDLE(fi,POPs);
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
		if ((svp = hv_fetch(fihash, "direct_io",    9, 0)) != NULL)
			fi->direct_io   = SvIV(*svp);
		if ((svp = hv_fetch(fihash, "keep_cache",  10, 0)) != NULL)
			fi->keep_cache  = SvIV(*svp);
#endif
#if FUSE_VERSION >= 29
		if ((svp = hv_fetch(fihash, "nonseekable", 11, 0)) != NULL)
 			fi->nonseekable = SvIV(*svp);
#endif
	}
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("open end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_read (const char *file, char *buf, size_t buflen, off_t off,
		struct fuse_file_info *fi) {
	int rv;
#ifndef PERL_HAS_64BITINT
	char *temp;
#endif
	FUSE_CONTEXT_PRE;
	DEBUGf("read begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(file ? sv_2mortal(newSVpv(file,0)) : &PL_sv_undef);
	XPUSHs(sv_2mortal(newSViv(buflen)));
#ifdef PERL_HAS_64BITINT
	XPUSHs(sv_2mortal(newSViv(off)));
#else
	if (asprintf(&temp, "%llu", off) == -1)
		croak("Memory allocation failure!");
	XPUSHs(sv_2mortal(newSVpv(temp, 0)));
	free(temp);
#endif
	XPUSHs(FH_GETHANDLE(fi));
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
	XPUSHs(file ? sv_2mortal(newSVpv(file,0)) : &PL_sv_undef);
	XPUSHs(sv_2mortal(newSVpvn(buf,buflen)));
#ifdef PERL_HAS_64BITINT
	XPUSHs(sv_2mortal(newSViv(off)));
#else
	if (asprintf(&temp, "%llu", off) == -1)
		croak("Memory allocation failure!");
	XPUSHs(sv_2mortal(newSVpv(temp, 0)));
	free(temp);
#endif
	XPUSHs(FH_GETHANDLE(fi));
	PUTBACK;
	rv = call_sv(MY_CXT.callback[16],G_SCALAR);
	SPAGAIN;
	rv = (rv ? POPi : 0);
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
	XPUSHs(file ? sv_2mortal(newSVpv(file,0)) : &PL_sv_undef);
	XPUSHs(FH_GETHANDLE(fi));
	PUTBACK;
	rv = call_sv(MY_CXT.callback[18],G_SCALAR);
	SPAGAIN;
	rv = (rv ? POPi : 0);
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
	XPUSHs(file ? sv_2mortal(newSVpv(file,0)) : &PL_sv_undef);
	XPUSHs(sv_2mortal(newSViv(flags)));
	XPUSHs(FH_GETHANDLE(fi));
	PUTBACK;
	rv = call_sv(MY_CXT.callback[19],G_SCALAR);
	SPAGAIN;
	rv = (rv ? POPi : 0);
	FH_RELEASEHANDLE(fi);
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
	XPUSHs(file ? sv_2mortal(newSVpv(file,0)) : &PL_sv_undef);
	XPUSHs(sv_2mortal(newSViv(flags)));
	XPUSHs(FH_GETHANDLE(fi));
	PUTBACK;
	rv = call_sv(MY_CXT.callback[20],G_SCALAR);
	SPAGAIN;
	rv = (rv ? POPi : 0);
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("fsync end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

#if __FreeBSD__ >= 10
int _PLfuse_setxattr (const char *file, const char *name, const char *buf, size_t buflen, int flags, uint32_t position) {
#else
int _PLfuse_setxattr (const char *file, const char *name, const char *buf, size_t buflen, int flags) {
#endif
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
	rv = (rv ? POPi : 0);
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("setxattr end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

#if __FreeBSD__ >= 10
int _PLfuse_getxattr (const char *file, const char *name, char *buf, size_t buflen, uint32_t position) {
#else
int _PLfuse_getxattr (const char *file, const char *name, char *buf, size_t buflen) {
#endif
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
	rv = (rv ? POPi : 0);
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("removexattr end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

#if FUSE_VERSION >= 23
int _PLfuse_opendir(const char *file, struct fuse_file_info *fi) {
	int rv;
	FUSE_CONTEXT_PRE;
	DEBUGf("opendir begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	fi->fh = 0; /* Ensure it starts with 0 - important if they don't set it */
	PUTBACK;
	rv = call_sv(MY_CXT.callback[25], G_ARRAY);
	SPAGAIN;
	if (rv) {
		if (rv > 1) {
			FH_STOREHANDLE(fi, POPs);
		}
		rv = POPi;
	} else
		rv = 0;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("opendir end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;

}

int _PLfuse_readdir(const char *file, void *dirh, fuse_fill_dir_t dirfil,
                    off_t off, struct fuse_file_info *fi) {
	int prv = 0, rv;
	SV *sv, **svp, **swp;
	AV *av, *av2;
	struct stat st;
	bool st_filled = 0;
#ifndef PERL_HAS_64BITINT
	char *temp;
#endif
	FUSE_CONTEXT_PRE;
	DEBUGf("readdir begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(file ? sv_2mortal(newSVpv(file,0)) : &PL_sv_undef);
#ifdef PERL_HAS_64BITINT
	XPUSHs(sv_2mortal(newSViv(off)));
#else
	if (asprintf(&temp, "%llu", off) == -1)
		croak("Memory allocation failure!");
	XPUSHs(sv_2mortal(newSVpv(temp, 0)));
	free(temp);
#endif
	XPUSHs(FH_GETHANDLE(fi));
	PUTBACK;
	prv = call_sv(MY_CXT.callback[26],G_ARRAY);
	SPAGAIN;
	if (prv) {
		/* Should yield the bottom of the current stack... */
		swp = &TOPs - prv + 1;
		rv = POPi;
		memset(&st, 0, sizeof(struct stat));
		/* Sort of a hack to walk the stack in order, instead of reverse
		 * order - trying to explain to potential users why they need to
		 * reverse the order of this array would be confusing, at best. */
		while (swp <= &TOPs) {
			sv = *(swp++);
			if (!SvROK(sv) && SvPOK(sv))
			/* Just a bare SV (probably a string; hopefully a string) */
				dirfil(dirh, SvPVx_nolen(sv), NULL, 0);
			else if (SvROK(sv) && SvTYPE(av = (AV *)SvRV(sv)) == SVt_PVAV) {
				if (av_len(av) >= 2) {
					/* The third element of the array should be the args that
					 * would otherwise go to getattr(); a lot of filesystems
					 * will, or at least can, return that info as part of the
					 * enumeration process... */
					svp = av_fetch(av, 2, FALSE);
					if (SvROK(*svp) &&
							SvTYPE(av2 = (AV *)SvRV(*svp)) == SVt_PVAV &&
							av_len(av2) == 12) {
						st.st_dev     = SvIV(*(av_fetch(av2,  0, FALSE)));
						st.st_ino     = SvIV(*(av_fetch(av2,  1, FALSE)));
						st.st_mode    = SvIV(*(av_fetch(av2,  2, FALSE)));
						st.st_nlink   = SvIV(*(av_fetch(av2,  3, FALSE)));
						st.st_uid     = SvIV(*(av_fetch(av2,  4, FALSE)));
						st.st_gid     = SvIV(*(av_fetch(av2,  5, FALSE)));
						st.st_rdev    = SvIV(*(av_fetch(av2,  6, FALSE)));
						st.st_size    = SvNV(*(av_fetch(av2,  7, FALSE)));
						st.st_atime   = SvIV(*(av_fetch(av2,  8, FALSE)));
						st.st_mtime   = SvIV(*(av_fetch(av2,  9, FALSE)));
						st.st_ctime   = SvIV(*(av_fetch(av2, 10, FALSE)));
						st.st_blksize = SvIV(*(av_fetch(av2, 11, FALSE)));
						st.st_blocks  = SvIV(*(av_fetch(av2, 12, FALSE)));
						st_filled = 1;
					}
					else
						fprintf(stderr,"Extra SV didn't appear to be correct, ignoring\n");
					/* For now if the element isn't what we want, just
					 * quietly ignore it... */
				}
				if (av_len(av) >= 1) {
					char *entryname = SvPVx_nolen(*(av_fetch(av, 1, FALSE)));
					off_t elemnum = SvNV(*(av_fetch(av, 0, FALSE)));
					dirfil(dirh, entryname, st_filled ? &st : NULL, elemnum);
				}
				if (st_filled) {
					memset(&st, 0, sizeof(struct stat));
					st_filled = 0;
				}
			}
			else
				fprintf(stderr, "ERROR: Unknown entry passed via readdir\n");
		}
	} else {
		fprintf(stderr,"readdir() handler returned nothing!\n");
		rv = -ENOSYS;
	}
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("readdir end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_releasedir(const char *file, struct fuse_file_info *fi) {
	int rv;
	FUSE_CONTEXT_PRE;
	DEBUGf("releasedir begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(file ? sv_2mortal(newSVpv(file,0)) : &PL_sv_undef);
	XPUSHs(FH_GETHANDLE(fi));
	PUTBACK;
	rv = call_sv(MY_CXT.callback[27], G_SCALAR);
	SPAGAIN;
	rv = (rv ? POPi : 0);
	FH_RELEASEHANDLE(fi);
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("releasedir end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_fsyncdir(const char *file, int datasync,
                     struct fuse_file_info *fi) {
	int rv;
	FUSE_CONTEXT_PRE;
	DEBUGf("fsyncdir begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(file ? sv_2mortal(newSVpv(file,0)) : &PL_sv_undef);
	XPUSHs(sv_2mortal(newSViv(datasync)));
	XPUSHs(FH_GETHANDLE(fi));
	PUTBACK;
	rv = call_sv(MY_CXT.callback[28], G_SCALAR);
	SPAGAIN;
	rv = (rv ? POPi : 0);
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("fsyncdir end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

#if FUSE_VERSION >= 26
void *_PLfuse_init(struct fuse_conn_info *fc)
#else /* FUSE_VERSION < 26 */
void *_PLfuse_init(void)
#endif /* FUSE_VERSION >= 26 */
{
	void *rv = NULL;
	int prv;
	FUSE_CONTEXT_PRE;
	DEBUGf("init begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	PUTBACK;
	prv = call_sv(MY_CXT.callback[29], G_SCALAR);
	SPAGAIN;
	if (prv) {
		rv = POPs;
		if (rv == &PL_sv_undef)
			rv = NULL;
		else
			rv = SvREFCNT_inc((SV *)rv);
	}
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("init end: %p\n", rv);
	FUSE_CONTEXT_POST;
	return rv;
}

void _PLfuse_destroy(void *private_data) {
	FUSE_CONTEXT_PRE;
	DEBUGf("destroy begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(private_data ? (SV *)private_data : &PL_sv_undef);
	PUTBACK;
	call_sv(MY_CXT.callback[30], G_VOID);
	SPAGAIN;
	if (private_data)
		SvREFCNT_dec((SV *)private_data);
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("init end\n");
	FUSE_CONTEXT_POST;
}
#endif /* FUSE_VERSION >= 23 */

#if FUSE_VERSION >= 25
int _PLfuse_access(const char *file, int mask) {
	int rv;
	FUSE_CONTEXT_PRE;
	DEBUGf("access begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSViv(mask)));
	PUTBACK;
	rv = call_sv(MY_CXT.callback[31], G_SCALAR);
	SPAGAIN;
	rv = (rv ? POPi : 0);
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("access end: %d\n", rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_create(const char *file, mode_t mode, struct fuse_file_info *fi) {
	int rv;
	HV *fihash;
	FUSE_CONTEXT_PRE;
	DEBUGf("create begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSViv(mode)));
	XPUSHs(sv_2mortal(newSViv(fi->flags)));
	fi->fh = 0; /* Ensure it starts with 0 - important if they don't set it */
	/* Create a hashref containing the details from fi
	 * which we can look at or modify.
	 */
	fihash = newHV();
	(void) hv_store(fihash, "direct_io",    9, newSViv(fi->direct_io),   0);
	(void) hv_store(fihash, "keep_cache",  10, newSViv(fi->keep_cache),  0);
#if FUSE_VERSION >= 29
	(void) hv_store(fihash, "nonseekable", 11, newSViv(fi->nonseekable), 0);
#endif
	XPUSHs(sv_2mortal(newRV_noinc((SV*) fihash)));
	/* All hashref things done */

	PUTBACK;
	rv = call_sv(MY_CXT.callback[32], G_ARRAY);
	SPAGAIN;
	if (rv) {
		if (rv > 1) {
			FH_STOREHANDLE(fi,POPs);
		}
		rv = POPi;
	}
	else {
		fprintf(stderr, "create() handler returned nothing!\n");
		rv = -ENOSYS;
	}
	if (rv == 0) {
		/* Success, so copy the file handle which they returned */
		SV **svp;
		if ((svp = hv_fetch(fihash, "direct_io",    9, 0)) != NULL)
			fi->direct_io   = SvIV(*svp);
		if ((svp = hv_fetch(fihash, "keep_cache",  10, 0)) != NULL)
			fi->keep_cache  = SvIV(*svp);
#if FUSE_VERSION >= 29
		if ((svp = hv_fetch(fihash, "nonseekable", 11, 0)) != NULL)
			fi->nonseekable = SvIV(*svp);
#endif
	}
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("create end: %d\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_ftruncate(const char *file, off_t off, struct fuse_file_info *fi) {
	int rv;
#ifndef PERL_HAS_64BITINT
	char *temp;
#endif
	FUSE_CONTEXT_PRE;
	DEBUGf("ftruncate begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(file ? sv_2mortal(newSVpv(file,0)) : &PL_sv_undef);
#ifdef PERL_HAS_64BITINT
	XPUSHs(sv_2mortal(newSViv(off)));
#else
	if (asprintf(&temp, "%llu", off) == -1)
		croak("Memory allocation failure!");
	XPUSHs(sv_2mortal(newSVpv(temp, 0)));
	free(temp);
#endif
	XPUSHs(FH_GETHANDLE(fi));
	PUTBACK;
	rv = call_sv(MY_CXT.callback[33],G_SCALAR);
	SPAGAIN;
	rv = (rv ? POPi : 0);
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("ftruncate end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_fgetattr(const char *file, struct stat *result,
                     struct fuse_file_info *fi) {
	int rv;
	FUSE_CONTEXT_PRE;
	DEBUGf("fgetattr begin: %s\n",file);
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(file ? sv_2mortal(newSVpv(file,0)) : &PL_sv_undef);
	XPUSHs(FH_GETHANDLE(fi));
	PUTBACK;
	rv = call_sv(MY_CXT.callback[34],G_ARRAY);
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
	DEBUGf("fgetattr end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}
#endif /* FUSE_VERSION >= 25 */

#if FUSE_VERSION >= 26
int _PLfuse_lock(const char *file, struct fuse_file_info *fi, int cmd,
                 struct flock *lockinfo) {
	int rv;
	HV *lihash;
	SV *sv;
#ifndef PERL_HAS_64BITINT
	char *temp;
#endif
	FUSE_CONTEXT_PRE;
	DEBUGf("lock begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(file ? sv_2mortal(newSVpv(file,0)) : &PL_sv_undef);
	XPUSHs(sv_2mortal(newSViv(cmd)));
	lihash = newHV();
	if (lockinfo) {
		(void) hv_store(lihash, "l_type",   6, newSViv(lockinfo->l_type), 0);
		(void) hv_store(lihash, "l_whence", 8, newSViv(lockinfo->l_whence), 0);
#ifdef PERL_HAS_64BITINT
		sv = newSViv(lockinfo->l_start);
#else
		if (asprintf(&temp, "%llu", lockinfo->l_start) == -1)
			croak("Memory allocation failure!");
		sv = newSVpv(temp, 0);
		free(temp);
#endif
		(void) hv_store(lihash, "l_start",  7, sv, 0);
#ifdef PERL_HAS_64BITINT
		sv = newSViv(lockinfo->l_len);
#else
		if (asprintf(&temp, "%llu", lockinfo->l_len) == -1)
			croak("Memory allocation failure!");
		sv = newSVpv(temp, 0);
		free(temp);
#endif
		(void) hv_store(lihash, "l_len",    5, sv, 0);
		(void) hv_store(lihash, "l_pid",    5, newSViv(lockinfo->l_pid), 0);
	}
	XPUSHs(sv_2mortal(newRV_noinc((SV*) lihash)));
	XPUSHs(FH_GETHANDLE(fi));

	PUTBACK;
	rv = call_sv(MY_CXT.callback[35],G_SCALAR);
	SPAGAIN;
	rv = (rv ? POPi : 0);
	if (lockinfo && !rv) {
		/* Need to copy back any altered values from the hash into
		 * the struct... */
		SV **svp;
		if ((svp = hv_fetch(lihash, "l_type",   6, 0)) != NULL)
			lockinfo->l_type   = SvIV(*svp);
		if ((svp = hv_fetch(lihash, "l_whence", 8, 0)) != NULL)
			lockinfo->l_whence = SvIV(*svp);
		if ((svp = hv_fetch(lihash, "l_start",  7, 0)) != NULL)
			lockinfo->l_start  = SvNV(*svp);
		if ((svp = hv_fetch(lihash, "l_len",    5, 0)) != NULL)
			lockinfo->l_len    = SvNV(*svp);
		if ((svp = hv_fetch(lihash, "l_pid",    5, 0)) != NULL)
			lockinfo->l_pid    = SvIV(*svp);
	}
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("lock end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_utimens(const char *file, const struct timespec tv[2]) {
	int rv;
	FUSE_CONTEXT_PRE;
	DEBUGf("utimens begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(tv ? sv_2mortal(newSVnv(tv[0].tv_sec + (tv[0].tv_nsec / 1000000000.0))) : &PL_sv_undef);
	XPUSHs(tv ? sv_2mortal(newSVnv(tv[1].tv_sec + (tv[1].tv_nsec / 1000000000.0))) : &PL_sv_undef);
	PUTBACK;
	rv = call_sv(MY_CXT.callback[36],G_SCALAR);
	SPAGAIN;
	rv = (rv ? POPi : 0);
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("utimens end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

int _PLfuse_bmap(const char *file, size_t blocksize, uint64_t *idx) {
	int rv;
#ifndef PERL_HAS_64BITINT
	char *temp;
#endif
	FUSE_CONTEXT_PRE;
	DEBUGf("bmap begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSViv(blocksize)));
#ifdef PERL_HAS_64BITINT
	XPUSHs(sv_2mortal(newSViv(*idx)));
#else
	if (asprintf(&temp, "%llu", *idx) == -1)
		croak("Memory allocation failure!");
	XPUSHs(sv_2mortal(newSVpv(temp, 0)));
	free(temp);
#endif
	PUTBACK;
	rv = call_sv(MY_CXT.callback[37],G_ARRAY);
	SPAGAIN;
	if (rv > 0 && rv < 3) {
		if (rv == 2)
			*idx = POPn;
		rv = POPi;
	}
	else {
		fprintf(stderr, "bmap(): wrong number of values returned?\n");
		rv = -ENOSYS;
	}
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("bmap end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}
#endif /* FUSE_VERSION >= 26 */

#if FUSE_VERSION >= 28
int _PLfuse_ioctl(const char *file, int cmd, void *arg,
                  struct fuse_file_info *fi, unsigned int flags, void *data) {
	int rv;
	FUSE_CONTEXT_PRE;
	DEBUGf("ioctl begin\n");
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(file,0)));
	XPUSHs(sv_2mortal(newSViv(cmd)));
    XPUSHs(sv_2mortal(newSViv((uintptr_t)arg)));
	XPUSHs(sv_2mortal(newSViv(flags)));
	if (_IOC_DIR(cmd) & _IOC_READ)
		XPUSHs(sv_2mortal(newSVpvn(data, _IOC_SIZE(cmd))));
	else
		XPUSHs(&PL_sv_undef);
	XPUSHs(FH_GETHANDLE(fi));
	PUTBACK;
	rv = call_sv(MY_CXT.callback[39],G_ARRAY);
	SPAGAIN;
	if (_IOC_DIR(cmd) & _IOC_WRITE) {
		if (rv == 2) {
			SV *sv = POPs;
			size_t len;
			char *rdata = SvPV(sv, len);
            rv--;

			if (len > _IOC_SIZE(cmd)) {
				fprintf(stderr, "ioctl(): returned data was too large for data area\n");
				rv = -EFBIG;
			}
			else {
				memset(data, 0, _IOC_SIZE(cmd));
				memcpy(data, rdata, len);
			}
		}
		else {
			fprintf(stderr, "ioctl(): ioctl was a write op, but no data was returned from call?\n");
			rv = -EFAULT;
		}
	}
	if (rv > 0)
		rv = POPi;
	FREETMPS;
	LEAVE;
	PUTBACK;
	DEBUGf("ioctl end: %i\n",rv);
	FUSE_CONTEXT_POST;
	return rv;
}

#if 0
int _PLfuse_poll(const char *file, struct fuse_file_info *fi,
                 struct fuse_pollhandle *ph, unsigned *reventsp) {

}
#endif
#endif /* FUSE_VERSION >= 28 */

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
#if FUSE_VERSION >= 23
opendir:		_PLfuse_opendir, 
readdir:		_PLfuse_readdir,
releasedir:		_PLfuse_releasedir,
fsyncdir:		_PLfuse_fsyncdir,
init:			_PLfuse_init,
destroy:		_PLfuse_destroy,
#endif /* FUSE_VERSION >= 23 */
#if FUSE_VERSION >= 25
access:			_PLfuse_access,
create:			_PLfuse_create,
ftruncate:		_PLfuse_ftruncate,
fgetattr:		_PLfuse_fgetattr,
#endif /* FUSE_VERSION >= 25 */
#if FUSE_VERSION >= 26
lock:			_PLfuse_lock,
utimens:		_PLfuse_utimens,
bmap:			_PLfuse_bmap,
#endif /* FUSE_VERSION >= 26 */
#if FUSE_VERSION >= 28
ioctl:			_PLfuse_ioctl,
#if 0
poll:			_PLfuse_poll,
#endif
#endif /* FUSE_VERSION >= 28 */
};

MODULE = Fuse		PACKAGE = Fuse
PROTOTYPES: DISABLE

BOOT:
	MY_CXT_INIT;
#ifdef USE_ITHREADS
	MY_CXT.self = aTHX;
#endif

void
CLONE(...)
	PREINIT:
#ifdef USE_ITHREADS
		int i;
		dTHX;
#endif
	CODE:
#ifdef USE_ITHREADS
		MY_CXT_CLONE;
		tTHX parent = MY_CXT.self;
		MY_CXT.self = my_perl;
#if (PERL_VERSION < 10) || (PERL_VERSION == 10 && PERL_SUBVERSION <= 0)
		/* CLONE entered without a pointer table, so we can't safely clone static data */
		if(!PL_ptr_table) {
			for(i=0;i<N_CALLBACKS;i++) {
				MY_CXT.callback[i] = NULL;
			}
			MY_CXT.handles = newHV();
		} else
#endif
		{
			CLONE_PARAMS *clone_param;
#if (PERL_VERSION > 13) || (PERL_VERSION == 13 && PERL_SUBVERSION >= 2)
			clone_param = Perl_clone_params_new(parent, aTHX);
#else
			CLONE_PARAMS raw_param;
			raw_param.flags = 0;
			raw_param.proto_perl = parent;
			raw_param.stashes = (AV*)sv_2mortal((SV*)newAV());
			clone_param = &raw_param;
#endif
			for(i=0;i<N_CALLBACKS;i++) {
				MY_CXT.callback[i] = sv_dup(MY_CXT.callback[i], clone_param);
			}
			MY_CXT.handles = (HV*)sv_dup((SV*)MY_CXT.handles, clone_param);
#if (PERL_VERSION > 13) || (PERL_VERSION == 13 && PERL_SUBVERSION >= 2)
			Perl_clone_params_del(clone_param);
#endif
		}
#endif

SV*
fuse_get_context()
	PREINIT:
	struct fuse_context *fc;
	CODE:
	fc = fuse_get_context();
	if(fc) {
		HV *hash = newHV();
		(void) hv_store(hash, "uid",   3, newSViv(fc->uid), 0);
		(void) hv_store(hash, "gid",   3, newSViv(fc->gid), 0);
		(void) hv_store(hash, "pid",   3, newSViv(fc->pid), 0);
		if (fc->private_data)
			(void) hv_store(hash, "private", 7, fc->private_data, 0);
#if FUSE_VERSION >= 28
		(void) hv_store(hash, "umask", 5, newSViv(fc->umask), 0);
#endif /* FUSE_VERSION >= 28 */
		RETVAL = newRV_noinc((SV*)hash);
	} else {
		XSRETURN_UNDEF;
	}
	OUTPUT:
	RETVAL

SV *
fuse_version()
	CODE:
	RETVAL = newSVpvf("%d.%d", FUSE_MAJOR_VERSION, FUSE_MINOR_VERSION);
	OUTPUT:
	RETVAL

#ifndef __FreeBSD__
SV *
XATTR_CREATE()
	CODE:
	RETVAL = newSViv(XATTR_CREATE);
	OUTPUT:
	RETVAL

SV *
XATTR_REPLACE()
	CODE:
	RETVAL = newSViv(XATTR_REPLACE);
	OUTPUT:
	RETVAL

#endif

void
perl_fuse_main(...)
	PREINIT:
	struct fuse_operations fops;
	int i, debug;
	char *mountpoint;
	char *mountopts;
	struct fuse_args args = FUSE_ARGS_INIT(0, NULL);
	struct fuse_chan *fc;
	dMY_CXT;
	INIT:
	if(items != N_CALLBACKS + 5) {
		fprintf(stderr,"Perl<->C inconsistency or internal error\n");
		XSRETURN_UNDEF;
	}
	memset(&fops, 0, sizeof(struct fuse_operations));
	CODE:
	debug = SvIV(ST(0));
	MY_CXT.threaded = SvIV(ST(1));
	MY_CXT.handles = (HV*)(sv_2mortal((SV*)(newHV())));
	if(MY_CXT.threaded) {
#ifdef FUSE_USE_ITHREADS
		master_interp = aTHX;
		MUTEX_INIT(&MY_CXT.mutex);
		SvSHARE((SV*)(MY_CXT.handles));
#else
		fprintf(stderr,"FUSE warning: Your script has requested multithreaded "
		               "mode, but your perl was not built with a supported "
		               "thread model. Threads are disabled.\n");
		MY_CXT.threaded = 0;
#endif
	}
	mountpoint = SvPV_nolen(ST(2));
	mountopts = SvPV_nolen(ST(3));
#if FUSE_VERSION >= 28
	fops.flag_nullpath_ok = SvIV(ST(4));
#endif /* FUSE_VERSION >= 28 */
	for(i=0;i<N_CALLBACKS;i++) {
		SV *var = ST(i+5);
		/* allow symbolic references, or real code references. */
		if(SvOK(var) && (SvPOK(var) || (SvROK(var) && SvTYPE(SvRV(var)) == SVt_PVCV))) {
			void **tmp1 = (void**)&_available_ops, **tmp2 = (void**)&fops;
			/* Dirty hack, to keep anything from overwriting the
			 * flag area with a pointer. There should never be
			 * anything passed as 'junk', but this prevents
			 * someone from doing it and screwing things up... */
			if (i == 38)
				continue;
			tmp2[i] = tmp1[i];
			MY_CXT.callback[i] = var;
		} else if(SvOK(var)) {
			croak("invalid callback (%i) passed to perl_fuse_main "
			      "(%s is not a string, code ref, or undef).\n",
			      i+5,SvPVbyte_nolen(var));
		} else {
			MY_CXT.callback[i] = NULL;
		}
	}
	/*
	 * XXX: What comes here is just a ridiculous use of the option parsing API
	 * to hack on compatibility with other parts of the new API. First and
	 * foremost, real C argc/argv would be good to get at...
	 */
	if ((mountopts || debug) && fuse_opt_add_arg(&args, "") == -1) {
		fuse_opt_free_args(&args);
		croak("out of memory\n");
	}
	if (mountopts && strcmp("", mountopts) &&
	     (fuse_opt_add_arg(&args, "-o") == -1 ||
	     fuse_opt_add_arg(&args, mountopts) == -1)) {
		fuse_opt_free_args(&args);
		croak("out of memory\n");
	}
	if (debug && fuse_opt_add_arg(&args, "-d") == -1) {
		fuse_opt_free_args(&args);
		croak("out of memory\n");
	}
	fc = fuse_mount(mountpoint,&args);
	if (fc == NULL)
		croak("could not mount fuse filesystem!\n");
#ifndef __NetBSD__
	if(MY_CXT.threaded) {
		fuse_loop_mt(fuse_new(fc,&args,&fops,sizeof(fops),NULL));
	} else
#endif
		fuse_loop(fuse_new(fc,&args,&fops,sizeof(fops),NULL));
	fuse_unmount(mountpoint,fc);
	fuse_opt_free_args(&args);
