#ifndef RAS_OSLocking
#define RAS_OSLocking

#include <stdbool.h>

#if __has_feature(nullability)
#define RAS_NULLABLE _Nullable
#define RAS_NONNULL _Nonnull
#else
#define RAS_NULLABLE
#define RAS_NONNULL
#endif

#if __has_attribute(swift_name)
#define RAS_SWIFT_NAME(x) __attribute__((swift_name(x)))
#else
#define RAS_SWIFT_NAME(x)
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

RAS_SWIFT_NAME("UnsafeUnfairLock")
typedef struct ras_lock {
	const void * RAS_NONNULL ptr;
} ras_lock_t;

/// Initialize an unmanaged unfair lock.
///
/// @note Destroy the lock by passing it to `free(_:)`.
///
/// @warning Calling the function on unsupported platforms would result in
///            SIGABRT.
///
/// @return An opaque pointer to the unfair lock.
RAS_NOTHROW_NONNULL
RAS_SWIFT_NAME("UnsafeUnfairLock.init(_usesUnfairLock:)")
extern const ras_lock_t _ras_lock_create(bool);

RAS_NOTHROW_NONNULL
RAS_SWIFT_NAME("UnsafeUnfairLock.destroy(self:)")
extern void _ras_lock_destroy(const ras_lock_t);

RAS_NOTHROW_NONNULL
RAS_SWIFT_NAME("UnsafeUnfairLock.lock(self:)")
extern void _ras_lock_lock(const ras_lock_t);

RAS_NOTHROW_NONNULL
RAS_SWIFT_NAME("UnsafeUnfairLock.unlock(self:)")
extern void _ras_lock_unlock(const ras_lock_t);

RAS_NOTHROW_NONNULL
RAS_SWIFT_NAME("UnsafeUnfairLock.try(self:)")
extern bool _ras_lock_trylock(const ras_lock_t);

#endif /* RAS_OSLocking */
