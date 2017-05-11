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
internal struct AtomicState<State: RawRepresentable> where State.RawValue == Int32 {
	internal typealias Transition = (expected: State, next: State)
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
	private var value: Int32

	/// Create a finite state machine with the specified initial state.
	///
	/// - parameters:
	///   - initial: The desired initial state.
	internal init(_ initial: State) {
		value = initial.rawValue
	}

	/// Compare the current state with the specified state.
	///
	/// - parameters:
	///   - expected: The expected state.
	///
	/// - returns: `true` if the current state matches the expected state.
	///            `false` otherwise.
	internal mutating func `is`(_ expected: State) -> Bool {
		return withUnsafeMutablePointer(to: &value) { valuePointer in
			return OSAtomicCompareAndSwap32Barrier(expected.rawValue,
			                                       expected.rawValue,
			                                       valuePointer)
		}
	}

	/// Try to transition from the expected current state to the specified next
	/// state.
	///
	/// - parameters:
	///   - expected: The expected state.
	///   - next: The state to transition to.
	///
	/// - returns: `true` if the transition succeeds. `false` otherwise.
	internal mutating func tryTransition(from expected: State, to next: State) -> Bool {
		return withUnsafeMutablePointer(to: &value) { valuePointer in
			return OSAtomicCompareAndSwap32Barrier(expected.rawValue,
			                                       next.rawValue,
			                                       valuePointer)
		}
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
	internal mutating func `is`(_ expected: State) -> Bool {
		return value.modify { $0 == expected.rawValue }
	}

	/// Try to transition from the expected current state to the specified next
	/// state.
	///
	/// - parameters:
	///   - expected: The expected state.
	///
	/// - returns: `true` if the transition succeeds. `false` otherwise.
	internal mutating func tryTransition(from expected: State, to next: State) -> Bool {
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
	#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
	@available(iOS 10.0, *)
	@available(macOS 10.12, *)
	@available(tvOS 10.0, *)
	@available(watchOS 3.0, *)
	internal final class UnfairLock: Lock {
		private var _lock: os_unfair_lock

		override init() {
			_lock = os_unfair_lock()
			super.init()
		}

		override func lock() {
			withUnsafeMutablePointer(to: &_lock, os_unfair_lock_lock)
		}

		override func unlock() {
			withUnsafeMutablePointer(to: &_lock, os_unfair_lock_unlock)
		}

		override func `try`() -> Bool {
			return withUnsafeMutablePointer(to: &_lock, os_unfair_lock_trylock)
		}
	}
	#endif

	internal final class PthreadLock: Lock {
		private var _lock: pthread_mutex_t

		override init() {
			_lock = pthread_mutex_t()

			let status = withUnsafeMutablePointer(to: &_lock) { pthread_mutex_init($0, nil) }
			assert(status == 0, "Unexpected pthread mutex error code: \(status)")

			super.init()
		}

		override func lock() {
			let status = withUnsafeMutablePointer(to: &_lock, pthread_mutex_lock)
			assert(status == 0, "Unexpected pthread mutex error code: \(status)")
		}

		override func unlock() {
			let status = withUnsafeMutablePointer(to: &_lock, pthread_mutex_unlock)
			assert(status == 0, "Unexpected pthread mutex error code: \(status)")
		}

		override func `try`() -> Bool {
			let status = withUnsafeMutablePointer(to: &_lock, pthread_mutex_trylock)
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
			let status = withUnsafeMutablePointer(to: &_lock, pthread_mutex_destroy)
			assert(status == 0, "Unexpected pthread mutex error code: \(status)")
		}
	}

	static func make() -> Lock {
		#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
		if #available(*, iOS 10.0, macOS 10.12, tvOS 10.0, watchOS 3.0) {
			return UnfairLock()
		}
		#endif

		return PthreadLock()
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


/// An atomic variable which uses a recursive lock.
internal final class RecursiveAtomic<Value> {
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
