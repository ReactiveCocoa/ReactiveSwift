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
#else
internal struct os_unfair_lock_s {}
internal typealias os_unfair_lock_t = UnsafeMutablePointer<os_unfair_lock_s>
internal typealias os_unfair_lock = os_unfair_lock_s
internal func os_unfair_lock_lock(_ lock: os_unfair_lock_t) { fatalError() }
internal func os_unfair_lock_unlock(_ lock: os_unfair_lock_t) { fatalError() }
internal func os_unfair_lock_trylock(_ lock: os_unfair_lock_t) -> Bool { fatalError() }
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
	///   - next: The state to transition to.
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
	///   - next: The state to transition to.
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

/// An unfair lock which requires manual deallocation. It does not guarantee
/// waiting threads to be waken in the lock acquisition order.
internal enum UnsafeUnfairLock {
	case mutex(UnsafeMutablePointer<pthread_mutex_t>)

	@available(macOS 10.12, iOS 10, tvOS 10, watchOS 3, *)
	case unfairLock(os_unfair_lock_t)

	internal init(label: String = "") {
		#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
		if #available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
			let lock = os_unfair_lock_t.allocate(capacity: 1)
			lock.initialize(to: os_unfair_lock())

			self = .unfairLock(lock)
			return
		}
		#endif

		let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
		mutex.initialize(to: pthread_mutex_t())

		let result = pthread_mutex_init(mutex, nil)
		if result != 0 {
			preconditionFailure("Failed to initialize mutex with error \(result).")
		}

		self = .mutex(mutex)
	}

	internal func destroy() {
		switch self {
		case let .unfairLock(lock):
			lock.deinitialize()
			lock.deallocate(capacity: 1)

		case let .mutex(mutex):
			let result = pthread_mutex_destroy(mutex)
			if result != 0 {
				preconditionFailure("Failed to destroy mutex with error \(result).")
			}

			mutex.deinitialize()
			mutex.deallocate(capacity: 1)
		}
	}

	internal func lock() {
		switch self {
		case let .unfairLock(lock):
			if #available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
				os_unfair_lock_lock(lock)
			} else {
				fatalError("Unexpected miscompliation.")
			}

		case let .mutex(mutex):
			let result = pthread_mutex_lock(mutex)
			if result != 0 {
				preconditionFailure("Failed to lock \(self) with error \(result).")
			}
		}
	}

	internal func unlock() {
		switch self {
		case let .unfairLock(lock):
			if #available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
				os_unfair_lock_unlock(lock)
			} else {
				fatalError("Unexpected miscompliation.")
			}

		case let .mutex(mutex):
			let result = pthread_mutex_unlock(mutex)
			if result != 0 {
				preconditionFailure("Failed to unlock \(self) with error \(result).")
			}
		}
	}

	internal func `try`() -> Bool {
		switch self {
		case let .unfairLock(lock):
			if #available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
				return os_unfair_lock_trylock(lock)
			} else {
				fatalError("Unexpected miscompliation.")
			}

		case let .mutex(mutex):
			let result = pthread_mutex_trylock(mutex)
			switch result {
			case 0:
				return true
			case EBUSY:
				return false
			default:
				preconditionFailure("Failed to lock \(self) with error \(result).")
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
