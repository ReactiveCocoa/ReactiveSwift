//
//  Disposable.swift
//  ReactiveSwift
//
//  Created by Justin Spahr-Summers on 2014-06-02.
//  Copyright (c) 2014 GitHub. All rights reserved.
//

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import MachO
#endif

/// Represents something that can be “disposed”, usually associated with freeing
/// resources or canceling work.
public protocol Disposable: class {
	/// Whether this disposable has been disposed already.
	var isDisposed: Bool { get }

	/// Disposing of the resources represented by `self`. If `self` has already
	/// been disposed of, it does nothing.
	///
	/// - note: Implementations must issue a memory barrier.
	func dispose()
}

private struct DisposableState {
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
	private var _isDisposed: Int32

	fileprivate var isDisposed: Bool {
		mutating get {
			return OSAtomicCompareAndSwap32(1, 1, &_isDisposed)
		}
	}

	fileprivate init() {
		_isDisposed = 0
	}

	fileprivate mutating func dispose() -> Bool {
		return OSAtomicCompareAndSwap32Barrier(0, 1, &_isDisposed)
	}
#else
	private let _isDisposed: Atomic<Bool>

	fileprivate var isDisposed: Bool {
		mutating get {
			return _isDisposed.value
		}
	}

	fileprivate init() {
		_isDisposed = Atomic(false)
	}

	fileprivate mutating func dispose() -> Bool {
		return !_isDisposed.swap(true)
	}
#endif
}

/// A type-erased disposable that forwards operations to an underlying disposable.
public final class AnyDisposable: Disposable {
	private let disposable: Disposable

	public var isDisposed: Bool {
		return disposable.isDisposed
	}

	public init(_ disposable: Disposable) {
		self.disposable = disposable
	}

	public func dispose() {
		disposable.dispose()
	}
}

/// A disposable that only flips `isDisposed` upon disposal, and performs no other
/// work.
public final class SimpleDisposable: Disposable {
	private var state = DisposableState()

	public var isDisposed: Bool {
		return state.isDisposed
	}

	public init() {}

	public func dispose() {
		_ = state.dispose()
	}
}

/// A disposable that will run an action upon disposal.
public final class ActionDisposable: Disposable {
	private var action: (() -> Void)?
	private var state: DisposableState

	public var isDisposed: Bool {
		return state.isDisposed
	}

	/// Initialize the disposable to run the given action upon disposal.
	///
	/// - parameters:
	///   - action: A closure to run when calling `dispose()`.
	public init(action: @escaping () -> Void) {
		self.action = action
		self.state = DisposableState()
	}

	public func dispose() {
		if state.dispose() {
			action?()
			action = nil
		}
	}
}

/// A disposable that will dispose of any number of other disposables.
public final class CompositeDisposable: Disposable {
	private let disposables: Atomic<Bag<Disposable>?>
	private var state: DisposableState

	/// Represents a handle to a disposable previously added to a
	/// CompositeDisposable.
	public final class DisposableHandle {
		private let bagToken: Atomic<RemovalToken?>
		private weak var disposable: CompositeDisposable?

		fileprivate static let empty = DisposableHandle()

		fileprivate init() {
			self.bagToken = Atomic(nil)
		}

		fileprivate init(bagToken: RemovalToken, disposable: CompositeDisposable) {
			self.bagToken = Atomic(bagToken)
			self.disposable = disposable
		}

		/// Remove the pointed-to disposable from its `CompositeDisposable`.
		///
		/// - note: This is useful to minimize memory growth, by removing
		///         disposables that are no longer needed.
		public func remove() {
			if let token = bagToken.swap(nil) {
				_ = disposable?.disposables.modify {
					$0?.remove(using: token)
				}
			}
		}
	}

	public var isDisposed: Bool {
		return state.isDisposed
	}

	/// Initialize a `CompositeDisposable` containing the given sequence of
	/// disposables.
	///
	/// - parameters:
	///   - disposables: A collection of objects conforming to the `Disposable`
	///                  protocol
	public init<S: Sequence>(_ disposables: S)
		where S.Iterator.Element == Disposable
	{
		var bag: Bag<Disposable> = Bag()

		for disposable in disposables {
			bag.insert(disposable)
		}

		self.disposables = Atomic(bag)
		self.state = DisposableState()
	}
	
	/// Initialize a `CompositeDisposable` containing the given sequence of
	/// disposables.
	///
	/// - parameters:
	///   - disposables: A collection of objects conforming to the `Disposable`
	///                  protocol
	public convenience init<S: Sequence>(_ disposables: S)
		where S.Iterator.Element == Disposable?
	{
		self.init(disposables.flatMap { $0 })
	}

	/// Initializes an empty `CompositeDisposable`.
	public convenience init() {
		self.init([Disposable]())
	}

	public func dispose() {
		if state.dispose() {
			if let ds = disposables.swap(nil) {
				for d in ds.reversed() {
					d.dispose()
				}
			}
		}
	}

	/// Add the given disposable to the list, then return a handle which can
	/// be used to opaquely remove the disposable later (if desired).
	///
	/// - parameters:
	///   - d: Optional disposable.
	///
	/// - returns: An instance of `DisposableHandle` that can be used to
	///            opaquely remove the disposable later (if desired).
	@discardableResult
	public func add(_ d: Disposable?) -> DisposableHandle {
		guard let d = d else {
			return DisposableHandle.empty
		}

		let handle: DisposableHandle? = disposables.modify {
			return ($0?.insert(d)).map { DisposableHandle(bagToken: $0, disposable: self) }
		}

		if let handle = handle {
			return handle
		} else {
			d.dispose()
			return DisposableHandle.empty
		}
	}

	/// Add an ActionDisposable to the list.
	///
	/// - parameters:
	///   - action: A closure that will be invoked when `dispose()` is called.
	///
	/// - returns: An instance of `DisposableHandle` that can be used to
	///            opaquely remove the disposable later (if desired).
	@discardableResult
	public func add(_ action: @escaping () -> Void) -> DisposableHandle {
		return add(ActionDisposable(action: action))
	}
}

/// A disposable that, upon deinitialization, will automatically dispose of
/// another disposable.
public final class ScopedDisposable<InnerDisposable: Disposable>: Disposable {
	/// The disposable which will be disposed when the ScopedDisposable
	/// deinitializes.
	public let innerDisposable: InnerDisposable

	public var isDisposed: Bool {
		return innerDisposable.isDisposed
	}

	/// Initialize the receiver to dispose of the argument upon
	/// deinitialization.
	///
	/// - parameters:
	///   - disposable: A disposable to dispose of when deinitializing.
	public init(_ disposable: InnerDisposable) {
		innerDisposable = disposable
	}

	deinit {
		dispose()
	}

	public func dispose() {
		return innerDisposable.dispose()
	}
}

extension ScopedDisposable where InnerDisposable: AnyDisposable {
	/// Initialize the receiver to dispose of the argument upon
	/// deinitialization.
	///
	/// - parameters:
	///   - disposable: A disposable to dispose of when deinitializing, which
	///                 will be wrapped in an `AnyDisposable`.
	public convenience init(_ disposable: Disposable) {
		self.init(InnerDisposable(disposable))
	}
}

/// A disposable that will optionally dispose of another disposable.
public final class SerialDisposable: Disposable {
	private let _innerDisposable: Atomic<Disposable?>
	private var state: DisposableState

	public var isDisposed: Bool {
		return state.isDisposed
	}

	/// The inner disposable to dispose of.
	///
	/// Whenever this property is set (even to the same value!), the previous
	/// disposable is automatically disposed.
	public var innerDisposable: Disposable? {
		get {
			return _innerDisposable.value
		}

		set(d) {
			_innerDisposable.swap(d)?.dispose()
			if let d = d, isDisposed {
				d.dispose()
			}
		}
	}

	/// Initializes the receiver to dispose of the argument when the
	/// SerialDisposable is disposed.
	///
	/// - parameters:
	///   - disposable: Optional disposable.
	public init(_ disposable: Disposable? = nil) {
		self._innerDisposable = Atomic(disposable)
		self.state = DisposableState()
	}

	public func dispose() {
		if state.dispose() {
			_innerDisposable.swap(nil)?.dispose()
		}
	}
}

/// Adds the right-hand-side disposable to the left-hand-side
/// `CompositeDisposable`.
///
/// ````
///  disposable += producer
///      .filter { ... }
///      .map    { ... }
///      .start(observer)
/// ````
///
/// - parameters:
///   - lhs: Disposable to add to.
///   - rhs: Disposable to add.
///
/// - returns: An instance of `DisposableHandle` that can be used to opaquely
///            remove the disposable later (if desired).
@discardableResult
public func +=(lhs: CompositeDisposable, rhs: Disposable?) -> CompositeDisposable.DisposableHandle {
	return lhs.add(rhs)
}

/// Adds the right-hand-side `ActionDisposable` to the left-hand-side
/// `CompositeDisposable`.
///
/// ````
/// disposable += { ... }
/// ````
///
/// - parameters:
///   - lhs: Disposable to add to.
///   - rhs: Closure to add as a disposable.
///
/// - returns: An instance of `DisposableHandle` that can be used to opaquely
///            remove the disposable later (if desired).
@discardableResult
public func +=(lhs: CompositeDisposable, rhs: @escaping () -> ()) -> CompositeDisposable.DisposableHandle {
	return lhs.add(rhs)
}

/// Adds the right-hand-side disposable to the left-hand-side
/// `ScopedDisposable<CompositeDisposable>`.
///
/// ````
/// disposable += { ... }
/// ````
///
/// - parameters:
///   - lhs: Disposable to add to.
///   - rhs: Disposable to add.
///
/// - returns: An instance of `DisposableHandle` that can be used to opaquely
///            remove the disposable later (if desired).
@discardableResult
public func +=(lhs: ScopedDisposable<CompositeDisposable>, rhs: Disposable?) -> CompositeDisposable.DisposableHandle {
	return lhs.innerDisposable.add(rhs)
}

/// Adds the right-hand-side disposable to the left-hand-side
/// `ScopedDisposable<CompositeDisposable>`.
///
/// ````
/// disposable += { ... }
/// ````
///
/// - parameters:
///   - lhs: Disposable to add to.
///   - rhs: Closure to add as a disposable.
///
/// - returns: An instance of `DisposableHandle` that can be used to opaquely
///            remove the disposable later (if desired).
@discardableResult
public func +=(lhs: ScopedDisposable<CompositeDisposable>, rhs: @escaping () -> ()) -> CompositeDisposable.DisposableHandle {
	return lhs.innerDisposable.add(rhs)
}
