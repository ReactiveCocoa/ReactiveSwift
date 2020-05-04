import Foundation
import Dispatch

extension Signal.Observer {

	/// An initializer that accepts a closure accepting an event for the
	/// observer.
	///
	/// - parameters:
	///   - action: A closure to lift over received event.
	///   - interruptsOnDeinit: `true` if the observer should send an `interrupted`
	///                         event as it deinitializes. `false` otherwise.
	internal convenience init(action: @escaping Action, interruptsOnDeinit: Bool) {
	//	@available(*, deprecated, message:"Use `Observer.init(value:termination:interruptsOnDeinit:)` instead.")
		self.init(
			value: { action(.value($0)) },
			termination: { action(.init($0)) },
			interruptsOnDeinit: interruptsOnDeinit
		)
	}

	/// An initializer that accepts a closure accepting an event for the
	/// observer.
	///
	/// - parameters:
	///   - action: A closure to lift over received event.
	public convenience init(_ action: @escaping Action) {
	// @available(*, deprecated, message:"Use `Observer.init(value:termination:)` instead.")
		self.init(
			value: { action(.value($0)) },
			termination: { action(.init($0)) }
		)
	}
}

// MARK: Unavailable methods in ReactiveSwift 3.0.
extension Signal {
	@available(*, unavailable, message:"Use the `Signal.init` that accepts a two-argument generator.")
	public convenience init(_ generator: (Observer) -> Disposable?) { fatalError() }
}

extension Lifetime {
	@discardableResult
	@available(*, unavailable, message:"Use `observeEnded(_:)` with a method reference to `dispose()` instead.")
	public func add(_ d: Disposable?) -> Disposable? { fatalError() }
}

// MARK: Deprecated types
