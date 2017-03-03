#import <stdlib.h>
#import <stdint.h>
#import <pthread.h>
#import <errno.h>
#import "include/OSLocking.h"

// Pack a boolean flag into the least significant bit of the given pointer.
#define RAS_PACK(ptr, flag) (void*) (((uintptr_t) ptr) | (((uintptr_t) flag) & 0x01 ))

// Test if the given lock is a libplatform unfair lock.
#define RAS_IS_UNFAIR(lock) (((uintptr_t) lock.ptr) & 0x01)

// Unpack the real pointer from the given packed pointer.
#define RAS_GET_REAL_PTR(lock) (void *) (((uintptr_t) lock.ptr) & (UINTPTR_MAX << 0x01))

#ifdef DEBUG
#define RAS_PTHREAD_ASSERT(x) if (x != 0) abort();
#else
#define RAS_PTHREAD_ASSERT(x) x
#endif

#define RAS_LOCK_PTHREAD 0
#define RAS_LOCK_UNFAIR 1

const ras_lock_t _ras_lock_create(bool usesUnfairLock) {
	ras_lock_t lock;

#ifndef __clang_analyzer__
	if (usesUnfairLock) {
#ifndef __RAS_OS_UNFAIR_LOCK
		abort();
#else
		os_unfair_lock_t ref = (typeof(ref)) malloc(sizeof(os_unfair_lock));
		*ref = OS_UNFAIR_LOCK_INIT;
		lock.ptr = RAS_PACK(ref, RAS_LOCK_UNFAIR);
#endif
	} else {
		pthread_mutex_t* mutex = (typeof(mutex)) malloc(sizeof(pthread_mutex_t));
		int code = pthread_mutex_init(mutex, 0);
		if (code != 0) abort();

		lock.ptr = RAS_PACK(mutex, RAS_LOCK_PTHREAD);
	}
#endif

	return lock;
}

void _ras_lock_destroy(const ras_lock_t lock) {
	if (RAS_IS_UNFAIR(lock)) {
#ifndef __RAS_OS_UNFAIR_LOCK
		abort();
#else
		free(RAS_GET_REAL_PTR(lock));
#endif
	} else {
		pthread_mutex_t *mutex = (typeof(mutex)) RAS_GET_REAL_PTR(lock);
		int code = pthread_mutex_destroy(mutex);
		if (code != 0) abort();

		free(mutex);
	}
}

void _ras_lock_lock(const ras_lock_t lock) {
	if (RAS_IS_UNFAIR(lock)) {
#ifndef __RAS_OS_UNFAIR_LOCK
		abort();
#else
		os_unfair_lock_lock((os_unfair_lock_t) RAS_GET_REAL_PTR(lock));
#endif
	} else {
		RAS_PTHREAD_ASSERT(pthread_mutex_lock((pthread_mutex_t *) RAS_GET_REAL_PTR(lock)));
	}
}

void _ras_lock_unlock(const ras_lock_t lock) {
	if (RAS_IS_UNFAIR(lock)) {
#ifndef __RAS_OS_UNFAIR_LOCK
		abort();
#else
		os_unfair_lock_unlock((os_unfair_lock_t) RAS_GET_REAL_PTR(lock));
#endif
	} else {
		RAS_PTHREAD_ASSERT(pthread_mutex_unlock((pthread_mutex_t *) RAS_GET_REAL_PTR(lock)));
	}
}

bool _ras_lock_trylock(const ras_lock_t lock) {
	if (RAS_IS_UNFAIR(lock)) {
#ifndef __RAS_OS_UNFAIR_LOCK
		abort();
#else
		return os_unfair_lock_trylock((os_unfair_lock_t) RAS_GET_REAL_PTR(lock));
#endif
	} else {
		int code = pthread_mutex_trylock((pthread_mutex_t *) RAS_GET_REAL_PTR(lock));
		switch (code) {
		case 0: return true;
		case EBUSY: return false;
		default: abort();
		}
	}
}
