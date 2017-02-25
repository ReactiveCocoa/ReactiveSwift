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

private final class Lock {
	private var mutex: pthread_mutex_t

	private init(_ mutex: pthread_mutex_t) {
		self.mutex = mutex
	}

	deinit {
		let result = pthread_mutex_destroy(&mutex)
		precondition(result == 0, "Failed to destroy mutex with error \(result).")
	}

	@inline(__always)
	fileprivate func lock() {
		let result = pthread_mutex_lock(&mutex)
		precondition(result == 0, "Failed to lock \(self) with error \(result).")
	}

	@inline(__always)
	fileprivate func unlock() {
		let result = pthread_mutex_unlock(&mutex)
		precondition(result == 0, "Failed to unlock \(self) with error \(result).")
	}

	fileprivate static var nonRecursive: Lock {
		var mutex = pthread_mutex_t()
		let result = pthread_mutex_init(&mutex, nil)
		precondition(result == 0, "Failed to initialize mutex with error \(result).")
		return self.init(mutex)
	}

	fileprivate static var recursive: Lock {

		func checkSuccess(_ instruction: @autoclosure () -> Int32, _ label: String) {
			let result = instruction()
			precondition(result == 0, "Failed to initialize \(label) with error: \(result).")
		}

		var attr = pthread_mutexattr_t()
		checkSuccess(pthread_mutexattr_init(&attr), "mutex attributes")
		checkSuccess(pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE), "mutex attributes")
		
		defer { pthread_mutexattr_destroy(&attr) }

		var mutex = pthread_mutex_t()
		checkSuccess(pthread_mutex_init(&mutex, &attr), "mutex")

		return self.init(mutex)
	}
}

public enum AtomicLocking {
	case recursive
	case nonRecursive

	fileprivate var lock: Lock {
		switch self {
		case .recursive: return Lock.recursive
		case .nonRecursive: return Lock.nonRecursive
		}
	}
}

/// An atomic variable.
public final class Atomic<Value> {
	private let lock: Lock

	private var _value: Value {
		didSet {
			didSetObserver?(_value)
		}
	}

	private let didSetObserver: ((Value) -> Void)?

	/// Initialize the variable with the given initial value.
	///
	/// - parameters:
	///   - value: Initial value for `self`.
	public convenience init(_ value: Value) {
		self.init(value, locking: .nonRecursive, didSet: nil)
	}

	public init(_ value: Value, locking: AtomicLocking = .nonRecursive, didSet action: ((Value) -> Void)? = nil) {
		_value = value
		self.didSetObserver = action
		self.lock = locking.lock
	}

	/// Atomically get or set the value of the variable.
	public var value: Value {
		get {
			return withValue { $0 }
		}

		set(newValue) {
			swap(newValue)
		}
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
}
