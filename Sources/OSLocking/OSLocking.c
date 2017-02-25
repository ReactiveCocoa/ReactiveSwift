#import "stdlib.h"
#import "include/OSLocking.h"

void * _ras_os_unfair_lock_create() {
#ifndef __RAS_OS_UNFAIR_LOCK
	abort();
#else
	os_unfair_lock_t ref = (os_unfair_lock_t) malloc(sizeof(os_unfair_lock));
	*ref = OS_UNFAIR_LOCK_INIT;
	return ref;
#endif
}
