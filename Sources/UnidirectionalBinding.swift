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
public protocol BindingSourceProtocol {
	associatedtype Value
	associatedtype Error: Swift.Error

	/// Observe the binding source by sending any events to the given observer.
	@discardableResult
	func observe(_ observer: Observer<Value, Error>, during lifetime: Lifetime) -> Disposable?
}

extension Signal: BindingSourceProtocol {
	@discardableResult
	public func observe(_ observer: Observer, during lifetime: Lifetime) -> Disposable? {
		return self.take(during: lifetime).observe(observer)
	}
}

extension SignalProducer: BindingSourceProtocol {
	@discardableResult
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

/// Describes a target which can be bound.
public protocol BindingTargetProtocol: class {
	associatedtype Value

	/// The lifetime of `self`. The binding operators use this to determine when
	/// the binding should be torn down.
	var lifetime: Lifetime { get }

	/// Consume a value from the binding.
	func consume(_ value: Value)
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
	<Target: BindingTargetProtocol, Source: BindingSourceProtocol>
	(target: Target, source: Source) -> Disposable?
	where Source.Value == Target.Value, Source.Error == NoError
{
	// Alter the semantics of `BindingTarget` to not require it to be retained.
	// This is done here--and not in a separate function--so that all variants
	// of `<~` can get this behavior.
	let observer: Observer<Target.Value, NoError>
	if let target = target as? BindingTarget<Target.Value> {
		observer = Observer(value: { [setter = target.setter] in setter($0) })
	} else {
		observer = Observer(value: { [weak target] in target?.consume($0) })
	}

	return source.observe(observer, during: target.lifetime)
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
	<Target: BindingTargetProtocol, Source: BindingSourceProtocol>
	(target: Target, source: Source) -> Disposable?
	where Target.Value: OptionalProtocol, Source.Value == Target.Value.Wrapped, Source.Error == NoError
{
	// Alter the semantics of `BindingTarget` to not require it to be retained.
	// This is done here--and not in a separate function--so that all variants
	// of `<~` can get this behavior.
	let observer: Observer<Source.Value, NoError>
	if let target = target as? BindingTarget<Target.Value> {
		observer = Observer(value: { [setter = target.setter] in setter(Target.Value(reconstructing: $0)) })
	} else {
		observer = Observer(value: { [weak target] in target?.consume(Target.Value(reconstructing: $0)) })
	}

	return source.observe(observer, during: target.lifetime)
}

/// A binding target that can be used with the `<~` operator.
public final class BindingTarget<Value>: BindingTargetProtocol {
	public let lifetime: Lifetime
	fileprivate let setter: (Value) -> Void

	/// Creates a binding target.
	///
	/// - parameters:
	///   - lifetime: The expected lifetime of any bindings towards `self`.
	///   - setter: The action to consume values.
	public init(lifetime: Lifetime, setter: @escaping (Value) -> Void) {
		self.setter = setter
		self.lifetime = lifetime
	}

	/// Creates a binding target which consumes values on the specified scheduler.
	///
	/// - parameters:
	///   - scheduler: The scheduler on which the `setter` consumes the values.
	///   - lifetime: The expected lifetime of any bindings towards `self`.
	///   - setter: The action to consume values.
	public convenience init(on scheduler: SchedulerProtocol, lifetime: Lifetime, setter: @escaping (Value) -> Void) {
		let setter: (Value) -> Void = { value in
			scheduler.schedule {
				setter(value)
			}
		}
		self.init(lifetime: lifetime, setter: setter)
	}

	public func consume(_ value: Value) {
		setter(value)
	}
}
