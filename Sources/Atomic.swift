//
//  Atomic.swift
//  ReactiveSwift
//
//  Created by Justin Spahr-Summers on 2014-06-10.
//  Copyright (c) 2014 GitHub. All rights reserved.
//

import Foundation
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import MachO
#endif

/// A simple, generic lock-free finite state machine.
///
/// - warning: `deinitialize` must be called to dispose of the consumed memory.
internal struct UnsafeAtomicState<State: RawRepresentable> where State.RawValue == Int32 {
	internal typealias Transition = (expected: State, next: State)
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
	private let value: UnsafeMutablePointer<Int32>

	/// Create a finite state machine with the specified initial state.
	///
	/// - parameters:
	///   - initial: The desired initial state.
	internal init(_ initial: State) {
		value = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
		value.initialize(to: initial.rawValue)
	}

	/// Deinitialize the finite state machine.
	internal func deinitialize() {
		value.deinitialize()
		value.deallocate(capacity: 1)
	}

	/// Compare the current state with the specified state.
	///
	/// - parameters:
	///   - expected: The expected state.
	///
	/// - returns: `true` if the current state matches the expected state.
	///            `false` otherwise.
	internal func `is`(_ expected: State) -> Bool {
		return OSAtomicCompareAndSwap32Barrier(expected.rawValue,
		                                       expected.rawValue,
		                                       value)
	}

	/// Try to transition from the expected current state to the specified next
	/// state.
	///
	/// - parameters:
	///   - expected: The expected state.
	///   - next: The state to transition to.
	///
	/// - returns: `true` if the transition succeeds. `false` otherwise.
	internal func tryTransition(from expected: State, to next: State) -> Bool {
		return OSAtomicCompareAndSwap32Barrier(expected.rawValue,
		                                       next.rawValue,
		                                       value)
	}
#else
	private let value: Atomic<Int32>

	/// Create a finite state machine with the specified initial state.
	///
	/// - parameters:
	///   - initial: The desired initial state.
	internal init(_ initial: State) {
		value = Atomic(initial.rawValue)
	}

	/// Deinitialize the finite state machine.
	internal func deinitialize() {}

	/// Compare the current state with the specified state.
	///
	/// - parameters:
	///   - expected: The expected state.
	///
	/// - returns: `true` if the current state matches the expected state.
	///            `false` otherwise.
	internal func `is`(_ expected: State) -> Bool {
		return value.modify { $0 == expected.rawValue }
	}

	/// Try to transition from the expected current state to the specified next
	/// state.
	///
	/// - parameters:
	///   - expected: The expected state.
	///
	/// - returns: `true` if the transition succeeds. `false` otherwise.
	internal func tryTransition(from expected: State, to next: State) -> Bool {
		return value.modify { value in
			if value == expected.rawValue {
				value = next.rawValue
				return true
			}
			return false
		}
	}
#endif
}

/// `Lock` exposes `os_unfair_lock` on supported platforms, with pthread mutex as the
// fallback.
internal class Lock {
	// Both `UnfairLock` and `PthreadLock` use `ManagedBufferPointer` to allocate inline
	// storage for the lock. Inout reference to a stored property is deliberately avoided
	// because Swift does not make any guarantee on the memory location of a variable. It
	// is also prone to reabstractions made by the compiler, which may disrupt the
	// atomicity of synchronization primitives.
	//
	// https://github.com/apple/swift/blob/master/docs/OwnershipManifesto.md#memory
	// https://lists.swift.org/pipermail/swift-users/Week-of-Mon-20161205/004147.html

	#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
	@available(iOS 10.0, *)
	@available(macOS 10.12, *)
	@available(tvOS 10.0, *)
	@available(watchOS 3.0, *)
	internal final class UnfairLock: Lock {
		// Inline storage support.

		private func withLock<R>(_ body: (os_unfair_lock_t) -> R) -> R {
			return ManagedBufferPointer<os_unfair_lock, Never>(unsafeBufferObject: self)
				.withUnsafeMutablePointerToHeader(body)
		}

		override class func make() -> UnfairLock {
			let pointer = ManagedBufferPointer<os_unfair_lock, Never>(bufferClass: self, minimumCapacity: 0) { _, _ in
				return os_unfair_lock()
			}
			return unsafeDowncast(pointer.buffer, to: UnfairLock.self)
		}

		override private init() {}

		// Lock operations.

		override func lock() {
			withLock(os_unfair_lock_lock)
		}

		override func unlock() {
			withLock(os_unfair_lock_unlock)
		}

		override func `try`() -> Bool {
			return withLock(os_unfair_lock_trylock)
		}

		deinit {
			withLock { _ = $0.deinitialize() }
		}
	}
	#endif

	internal final class PthreadLock: Lock {
		// Inline storage support.

		private func withLock<R>(_ body: (UnsafeMutablePointer<pthread_mutex_t>) -> R) -> R {
			return ManagedBufferPointer<pthread_mutex_t, Never>(unsafeBufferObject: self)
				.withUnsafeMutablePointerToHeader(body)
		}

		override class func make() -> PthreadLock {
			return make(recursive: false)
		}

		class func make(recursive: Bool) -> PthreadLock {
			let pointer = ManagedBufferPointer<pthread_mutex_t, Never>(bufferClass: self, minimumCapacity: 0) { _, _ in
				return pthread_mutex_t()
			}

			pointer.withUnsafeMutablePointerToHeader { _lock in
				let attr = UnsafeMutablePointer<pthread_mutexattr_t>.allocate(capacity: 1)
				attr.initialize(to: pthread_mutexattr_t())
				pthread_mutexattr_init(attr)

				defer {
					pthread_mutexattr_destroy(attr)
					attr.deinitialize()
					attr.deallocate(capacity: 1)
				}

				#if DEBUG
					pthread_mutexattr_settype(attr, Int32(recursive ? PTHREAD_MUTEX_RECURSIVE : PTHREAD_MUTEX_ERRORCHECK))
				#else
					pthread_mutexattr_settype(attr, Int32(recursive ? PTHREAD_MUTEX_RECURSIVE : PTHREAD_MUTEX_NORMAL))
				#endif

				let status = pthread_mutex_init(_lock, attr)
				assert(status == 0, "Unexpected pthread mutex error code: \(status)")
			}

			return unsafeDowncast(pointer.buffer, to: PthreadLock.self)
		}

		override private init() {}

		// Lock operations.

		override func lock() {
			let status = withLock(pthread_mutex_lock)
			assert(status == 0, "Unexpected pthread mutex error code: \(status)")
		}

		override func unlock() {
			let status = withLock(pthread_mutex_unlock)
			assert(status == 0, "Unexpected pthread mutex error code: \(status)")
		}

		override func `try`() -> Bool {
			let status = withLock(pthread_mutex_trylock)
			switch status {
			case 0:
				return true
			case EBUSY:
				return false
			default:
				assertionFailure("Unexpected pthread mutex error code: \(status)")
				return false
			}
		}

		deinit {
			withLock { lock in
				let status = pthread_mutex_destroy(lock)
				assert(status == 0, "Unexpected pthread mutex error code: \(status)")

				_ = lock.deinitialize()
			}
		}
	}

	class func make() -> Lock {
		#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
		if #available(*, iOS 10.0, macOS 10.12, tvOS 10.0, watchOS 3.0) {
			return UnfairLock.make()
		}
		#endif

		return PthreadLock.make()
	}

	private init() {}

	func lock() { fatalError() }
	func unlock() { fatalError() }
	func `try`() -> Bool { fatalError() }
}

/// An atomic variable.
public final class Atomic<Value> {
	private let lock: Lock
	private var _value: Value

	/// Atomically get or set the value of the variable.
	public var value: Value {
		get {
			return withValue { $0 }
		}

		set(newValue) {
			swap(newValue)
		}
	}

	/// Initialize the variable with the given initial value.
	///
	/// - parameters:
	///   - value: Initial value for `self`.
	public init(_ value: Value) {
		_value = value
		lock = Lock.make()
	}

	/// Atomically modifies the variable.
	///
	/// - parameters:
	///   - action: A closure that takes the current value.
	///
	/// - returns: The result of the action.
	@discardableResult
	public func modify<Result>(_ action: (inout Value) throws -> Result) rethrows -> Result {
		lock.lock()
		defer { lock.unlock() }

		return try action(&_value)
	}
	
	/// Atomically perform an arbitrary action using the current value of the
	/// variable.
	///
	/// - parameters:
	///   - action: A closure that takes the current value.
	///
	/// - returns: The result of the action.
	@discardableResult
	public func withValue<Result>(_ action: (Value) throws -> Result) rethrows -> Result {
		lock.lock()
		defer { lock.unlock() }

		return try action(_value)
	}

	/// Atomically replace the contents of the variable.
	///
	/// - parameters:
	///   - newValue: A new value for the variable.
	///
	/// - returns: The old value.
	@discardableResult
	public func swap(_ newValue: Value) -> Value {
		return modify { (value: inout Value) in
			let oldValue = value
			value = newValue
			return oldValue
		}
	}
}
