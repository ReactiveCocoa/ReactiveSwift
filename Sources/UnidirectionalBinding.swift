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

	var producer: SignalProducer<Value, Error> { get }
}

extension Signal: BindingSource {
	public var producer: SignalProducer<Value, Error> {
		return SignalProducer(self)
	}
}

extension SignalProducer: BindingSource {}

/// Describes an entity which be bond towards.
public protocol BindingTargetProvider {
	associatedtype Value

	var bindingTarget: BindingTarget<Value> { get }
}

extension BindingTargetProvider {
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
	public static func <~
		<Source: BindingSource>
		(provider: Self, source: Source) -> Disposable?
		where Source.Value == Value, Source.Error == NoError
	{
		return source.producer
			.take(during: provider.bindingTarget.lifetime)
			.startWithValues(provider.bindingTarget.action)
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
	public static func <~
		<Source: BindingSource>
		(provider: Self, source: Source) -> Disposable?
		where Value == Source.Value?, Source.Error == NoError
	{
		return provider <~ source.producer.optionalize()
	}
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
	public init<S: Scheduler>(on scheduler: S, lifetime: Lifetime, action: @escaping (Value) -> Void) {
		let setter: (Value) -> Void = { value in
			scheduler.schedule {
				action(value)
			}
		}
		self.init(lifetime: lifetime, action: setter)
	}
}
