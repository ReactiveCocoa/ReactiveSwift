#ifndef RAS_OSLocking
#define RAS_OSLocking

#if __has_feature(nullability)
#define RAS_NULLABLE _Nullable
#define RAS_NONNULL _Nonnull
#else
#define RAS_NULLABLE
#define RAS_NONNULL
#endif

#if __GNUC__
#define RAS_NOTHROW_NONNULL __attribute__((__nothrow__ __nonnull__))
#else
#define RAS_NOTHROW_NONNULL
#endif

#if defined(__MACH__)
#import "Availability.h"
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 100000 || __MAC_OS_X_VERSION_MAX_ALLOWED >= 1012
#define __RAS_OS_UNFAIR_LOCK
#import "os/lock.h"
#endif
#endif

/// Initialize an unmanaged unfair lock.
///
/// @note Destroy the lock by passing it to `free(_:)`.
///
/// @warning Calling the function on unsupported platforms would result in
///            SIGABRT.
///
/// @return An opaque pointer to the unfair lock.
RAS_NOTHROW_NONNULL
extern void * RAS_NONNULL _ras_os_unfair_lock_create(void);

// Reexport the `os_unfair_*` functions to bypass the availability evaluations
// on the Swift imported declarations.
#ifndef __RAS_OS_UNFAIR_LOCK
const static void * RAS_NULLABLE _ras_os_unfair_lock = 0;
const static void * RAS_NULLABLE _ras_os_unfair_unlock = 0;
const static void * RAS_NULLABLE _ras_os_unfair_trylock = 0;
#else
const static void * RAS_NULLABLE _ras_os_unfair_lock = os_unfair_lock_lock;
const static void * RAS_NULLABLE _ras_os_unfair_unlock = os_unfair_lock_unlock;
const static void * RAS_NULLABLE _ras_os_unfair_trylock = os_unfair_lock_trylock;
#endif
#endif /* RAS_OSLocking */
