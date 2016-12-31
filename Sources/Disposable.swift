//
//  Disposable.swift
//  ReactiveSwift
//
//  Created by Justin Spahr-Summers on 2014-06-02.
//  Copyright (c) 2014 GitHub. All rights reserved.
//

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

/// Represents the state of a disposable.
private enum DisposableState: Int32 {
	/// The disposable is active.
	case active

	/// The disposable has been disposed.
	case disposed
}

extension AtomicStateProtocol where State == DisposableState {
	/// Try to transition from `active` to `disposed`.
	///
	/// - returns:
	///   `true` if the transition succeeds. `false` otherwise.
	@inline(__always)
	fileprivate func tryDispose() -> Bool {
		return tryTransition(from: .active, to: .disposed)
	}
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
	private var state = UnsafeAtomicState(DisposableState.active)

	public var isDisposed: Bool {
		return state.is(.disposed)
	}

	public init() {}

	public func dispose() {
		_ = state.tryDispose()
	}

	deinit {
		state.deinitialize()
	}
}

/// A disposable that will run an action upon disposal.
public final class ActionDisposable: Disposable {
	private var action: (() -> Void)?
	private var state: UnsafeAtomicState<DisposableState>

	public var isDisposed: Bool {
		return state.is(.disposed)
	}

	/// Initialize the disposable to run the given action upon disposal.
	///
	/// - parameters:
	///   - action: A closure to run when calling `dispose()`.
	public init(action: @escaping () -> Void) {
		self.action = action
		self.state = UnsafeAtomicState(DisposableState.active)
	}

	public func dispose() {
		if state.tryDispose() {
			action?()
			action = nil
		}
	}

	deinit {
		state.deinitialize()
	}
}

/// A disposable that will dispose of any number of other disposables.
public final class CompositeDisposable: Disposable {
	private let disposables: Atomic<Bag<Disposable>?>
	private var state: UnsafeAtomicState<DisposableState>

	/// Represents a handle to a disposable previously added to a
	/// CompositeDisposable.
	public final class DisposableHandle {
		private var state: UnsafeAtomicState<DisposableState>
		private var bagToken: RemovalToken?
		private weak var disposable: CompositeDisposable?

		fileprivate static let empty = DisposableHandle()

		fileprivate init() {
			self.state = UnsafeAtomicState(.disposed)
			self.bagToken = nil
		}

		deinit {
			state.deinitialize()
		}

		fileprivate init(bagToken: RemovalToken, disposable: CompositeDisposable) {
			self.state = UnsafeAtomicState(.active)
			self.bagToken = bagToken
			self.disposable = disposable
		}

		/// Remove the pointed-to disposable from its `CompositeDisposable`.
		///
		/// - note: This is useful to minimize memory growth, by removing
		///         disposables that are no longer needed.
		public func remove() {
			if state.tryDispose(), let token = bagToken {
				_ = disposable?.disposables.modify {
					$0?.remove(using: token)
				}
				bagToken = nil
				disposable = nil
			}
		}
	}

	public var isDisposed: Bool {
		return state.is(.disposed)
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
		self.state = UnsafeAtomicState(DisposableState.active)
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
		if state.tryDispose() {
			if let ds = disposables.swap(nil) {
				for d in ds {
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

	deinit {
		state.deinitialize()
	}
}

/// A disposable that, upon deinitialization, will automatically dispose of
/// its inner disposable.
public final class ScopedDisposable<Inner: Disposable>: Disposable {
	/// The disposable which will be disposed when the ScopedDisposable
	/// deinitializes.
	public let inner: Inner

	public var isDisposed: Bool {
		return inner.isDisposed
	}

	/// Initialize the receiver to dispose of the argument upon
	/// deinitialization.
	///
	/// - parameters:
	///   - disposable: A disposable to dispose of when deinitializing.
	public init(_ disposable: Inner) {
		inner = disposable
	}

	deinit {
		dispose()
	}

	public func dispose() {
		return inner.dispose()
	}
}

extension ScopedDisposable where Inner: AnyDisposable {
	/// Initialize the receiver to dispose of the argument upon
	/// deinitialization.
	///
	/// - parameters:
	///   - disposable: A disposable to dispose of when deinitializing, which
	///                 will be wrapped in an `AnyDisposable`.
	public convenience init(_ disposable: Disposable) {
		self.init(Inner(disposable))
	}
}

/// A disposable that disposes of its wrapped disposable, and allows its
/// wrapped disposable to be replaced.
public final class SerialDisposable: Disposable {
	private let _inner: Atomic<Disposable?>
	private var state: UnsafeAtomicState<DisposableState>

	public var isDisposed: Bool {
		return state.is(.disposed)
	}

	/// The current inner disposable to dispose of.
	///
	/// Whenever this property is set (even to the same value!), the previous
	/// disposable is automatically disposed.
	public var inner: Disposable? {
		get {
			return _inner.value
		}

		set(d) {
			_inner.swap(d)?.dispose()
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
		self._inner = Atomic(disposable)
		self.state = UnsafeAtomicState(DisposableState.active)
	}

	public func dispose() {
		if state.tryDispose() {
			_inner.swap(nil)?.dispose()
		}
	}

	deinit {
		state.deinitialize()
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
	return lhs.inner.add(rhs)
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
	return lhs.inner.add(rhs)
}
