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

#if SWIFT_PACKAGE
import OSLocking
#endif

/// Represents a finite state machine that can transit from one state to
/// another.
internal protocol AtomicStateProtocol {
	associatedtype State: RawRepresentable

	/// Try to transition from the expected current state to the specified next
	/// state.
	///
	/// - parameters:
	///   - expected: The expected state.
	///
	/// - returns:
	///   `true` if the transition succeeds. `false` otherwise.
	func tryTransition(from expected: State, to next: State) -> Bool
}

/// A simple, generic lock-free finite state machine.
///
/// - warning: `deinitialize` must be called to dispose of the consumed memory.
internal struct UnsafeAtomicState<State: RawRepresentable>: AtomicStateProtocol where State.RawValue == Int32 {
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
	/// - returns:
	///   `true` if the current state matches the expected state. `false`
	///   otherwise.
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
	///
	/// - returns:
	///   `true` if the transition succeeds. `false` otherwise.
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
	/// - returns:
	///   `true` if the current state matches the expected state. `false`
	///   otherwise.
	internal func `is`(_ expected: State) -> Bool {
		return value.modify { $0 == expected.rawValue }
	}

	/// Try to transition from the expected current state to the specified next
	/// state.
	///
	/// - parameters:
	///   - expected: The expected state.
	///
	/// - returns:
	///   `true` if the transition succeeds. `false` otherwise.
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

/// A reference counted version of `UnsafeUnfairLock`.
internal final class UnfairLock {
	let _lock: UnsafeUnfairLock

	internal init(label: String = "") {
		_lock = UnsafeUnfairLock(label: label)
	}

	deinit {
		_lock.destroy()
	}

	internal func lock() {
		_lock.lock()
	}

	internal func unlock() {
		_lock.unlock()
	}

	internal func `try`() -> Bool {
		return _lock.try()
	}
}

@_fixed_layout
internal struct UnsafeUnfairLock {
	@_fixed_layout
	private enum Implementation {
		case libplatform(UnsafeRawPointer)
		case pthread(UnsafeMutablePointer<pthread_mutex_t>)
	}

	private let storage: Implementation

	internal init(label: String = "") {
		#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
			if #available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
				storage = .libplatform(_ras_os_unfair_lock_create())
				return
			}
		#endif

		let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
		mutex.initialize(to: pthread_mutex_t())
		pthread_mutex_init(mutex, nil)

		storage = .pthread(mutex)
	}

	internal func destroy() {
		switch storage {
		case let .libplatform(lock):
			free(UnsafeMutableRawPointer(mutating: lock))

		case let .pthread(mutex):
			pthread_mutex_destroy(mutex)
			mutex.deinitialize()
			mutex.deallocate(capacity: 1)
		}
	}

	internal func lock() {
		switch storage {
		case let .libplatform(lock):
			typealias LockFunc = @convention(c) (UnsafeRawPointer) -> Void
			unsafeBitCast(_ras_os_unfair_lock, to: LockFunc.self)(lock)

		case let .pthread(mutex):
			let error = pthread_mutex_lock(mutex)
			if error != 0 {
				fatalError("Failed to lock a pthread mutex with error code \(error).")
			}
		}
	}

	internal func unlock() {
		switch storage {
		case let .libplatform(lock):
			typealias UnlockFunc = @convention(c) (UnsafeRawPointer) -> Void
			unsafeBitCast(_ras_os_unfair_unlock, to: UnlockFunc.self)(lock)

		case let .pthread(mutex):
			let error = pthread_mutex_unlock(mutex)
			if error != 0 {
				fatalError("Failed to unlock a pthread mutex with error code \(error).")
			}
		}
	}

	internal func `try`() -> Bool {
		switch storage {
		case let .libplatform(lock):
			typealias TryLockFunc = @convention(c) (UnsafeRawPointer) -> CBool
			return unsafeBitCast(_ras_os_unfair_trylock, to: TryLockFunc.self)(lock)

		case let .pthread(mutex):
			let error = pthread_mutex_trylock(mutex)
			switch error {
			case 0:
				return true
			case EBUSY:
				return false
			default:
				fatalError("Failed to lock a pthread mutex with error code \(error).")
			}
		}
	}
}

/// An atomic variable.
public final class Atomic<Value>: AtomicProtocol {
	private let lock: UnsafeUnfairLock
	private var _value: Value

	/// Atomically get or set the value of the variable.
	public var value: Value {
		get {
			lock.lock()
			let value = _value
			lock.unlock()

			return value
		}

		set {
			lock.lock()
			_value = newValue
			lock.unlock()
		}
	}

	/// Initialize the variable with the given initial value.
	/// 
	/// - parameters:
	///   - value: Initial value for `self`.
	public init(_ value: Value) {
		_value = value
		lock = UnsafeUnfairLock()
	}

	deinit {
		lock.destroy()
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


/// An atomic variable which uses a recursive lock.
internal final class RecursiveAtomic<Value>: AtomicProtocol {
	private let lock: NSRecursiveLock
	private var _value: Value
	private let didSetObserver: ((Value) -> Void)?

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
	///   - name: An optional name used to create the recursive lock.
	///   - action: An optional closure which would be invoked every time the
	///             value of `self` is mutated.
	internal init(_ value: Value, name: StaticString? = nil, didSet action: ((Value) -> Void)? = nil) {
		_value = value
		lock = NSRecursiveLock()
		lock.name = name.map(String.init(describing:))
		didSetObserver = action
	}

	/// Atomically modifies the variable.
	///
	/// - parameters:
	///   - action: A closure that takes the current value.
	///
	/// - returns: The result of the action.
	@discardableResult
	func modify<Result>(_ action: (inout Value) throws -> Result) rethrows -> Result {
		lock.lock()
		defer {
			didSetObserver?(_value)
			lock.unlock()
		}

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
	func withValue<Result>(_ action: (Value) throws -> Result) rethrows -> Result {
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
