import Foundation
import Dispatch
import enum Result.NoError

precedencegroup BindingPrecedence {
	associativity: right

	// Binds tighter than assignment but looser than everything else
	higherThan: AssignmentPrecedence
}

infix operator <~ : BindingPrecedence

/// Describes a source which can be bound.
public protocol BindingSource {
	associatedtype Value
	associatedtype Error: Swift.Error

	/// Observe the binding source by sending any events to the given observer.
	@discardableResult
	func observe(_ observer: Observer<Value, Error>, during lifetime: Lifetime) -> Disposable?
}

extension Signal: BindingSource {
	@discardableResult
	@available(*, deprecated, message:"Use `take(during:)` and `observe` instead. `observe(_:during:)` would be removed in ReactiveSwift 2.0.")
	public func observe(_ observer: Observer, during lifetime: Lifetime) -> Disposable? {
		return self.take(during: lifetime).observe(observer)
	}
}

extension SignalProducer: BindingSource {
	@discardableResult
	@available(*, deprecated, message:"Use `take(during:)` and `start` instead. `observe(_:during:)` would be removed in ReactiveSwift 2.0.")
	public func observe(_ observer: ProducedSignal.Observer, during lifetime: Lifetime) -> Disposable? {
		var disposable: Disposable!

		self
			.take(during: lifetime)
			.startWithSignal { signal, signalDisposable in
				disposable = signalDisposable
				signal.observe(observer)
		}

		return disposable
	}
}

/// Describes an entity which be bond towards.
public protocol BindingTargetProvider {
	associatedtype Value

	var bindingTarget: BindingTarget<Value> { get }
}

/// Binds a source to a target, updating the target's value to the latest
/// value sent by the source.
///
/// - note: The binding will automatically terminate when the target is
///         deinitialized, or when the source sends a `completed` event.
///
/// ````
/// let property = MutableProperty(0)
/// let signal = Signal({ /* do some work after some time */ })
/// property <~ signal
/// ````
///
/// ````
/// let property = MutableProperty(0)
/// let signal = Signal({ /* do some work after some time */ })
/// let disposable = property <~ signal
/// ...
/// // Terminates binding before property dealloc or signal's
/// // `completed` event.
/// disposable.dispose()
/// ````
///
/// - parameters:
///   - target: A target to be bond to.
///   - source: A source to bind.
///
/// - returns: A disposable that can be used to terminate binding before the
///            deinitialization of the target or the source's `completed`
///            event.
@discardableResult
public func <~
	<Provider: BindingTargetProvider, Source: BindingSource>
	(provider: Provider, source: Source) -> Disposable?
	where Source.Value == Provider.Value, Source.Error == NoError
{
	return source.observe(Observer(value: provider.bindingTarget.action),
	                      during: provider.bindingTarget.lifetime)
}

/// Binds a source to a target, updating the target's value to the latest
/// value sent by the source.
///
/// - note: The binding will automatically terminate when the target is
///         deinitialized, or when the source sends a `completed` event.
///
/// ````
/// let property = MutableProperty(0)
/// let signal = Signal({ /* do some work after some time */ })
/// property <~ signal
/// ````
///
/// ````
/// let property = MutableProperty(0)
/// let signal = Signal({ /* do some work after some time */ })
/// let disposable = property <~ signal
/// ...
/// // Terminates binding before property dealloc or signal's
/// // `completed` event.
/// disposable.dispose()
/// ````
///
/// - parameters:
///   - target: A target to be bond to.
///   - source: A source to bind.
///
/// - returns: A disposable that can be used to terminate binding before the
///            deinitialization of the target or the source's `completed`
///            event.
@discardableResult
public func <~
	<Provider: BindingTargetProvider, Source: BindingSource>
	(provider: Provider, source: Source) -> Disposable?
	where Provider.Value: OptionalProtocol, Source.Value == Provider.Value.Wrapped, Source.Error == NoError
{
	let action = provider.bindingTarget.action
	return source.observe(Observer(value: { action(Provider.Value(reconstructing: $0)) }),
	                      during: provider.bindingTarget.lifetime)
}

/// A binding target that can be used with the `<~` operator.
public struct BindingTarget<Value>: BindingTargetProvider {
	public let lifetime: Lifetime
	public let action: (Value) -> Void

	public var bindingTarget: BindingTarget<Value> {
		return self
	}

	/// Creates a binding target.
	///
	/// - parameters:
	///   - lifetime: The expected lifetime of any bindings towards `self`.
	///   - action: The action to consume values.
	public init(lifetime: Lifetime, action: @escaping (Value) -> Void) {
		self.action = action
		self.lifetime = lifetime
	}

	/// Creates a binding target which consumes values on the specified scheduler.
	///
	/// - parameters:
	///   - scheduler: The scheduler on which the `setter` consumes the values.
	///   - lifetime: The expected lifetime of any bindings towards `self`.
	///   - action: The action to consume values.
	public init(on scheduler: Scheduler, lifetime: Lifetime, action: @escaping (Value) -> Void) {
		let setter: (Value) -> Void = { value in
			scheduler.schedule {
				action(value)
			}
		}
		self.init(lifetime: lifetime, action: setter)
	}
}
