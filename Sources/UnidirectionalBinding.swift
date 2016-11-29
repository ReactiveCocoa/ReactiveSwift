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
	
	/// Observe the binding source by sending any evenst to the given observer.
	@discardableResult
	func observe(_ observer: Observer<Value, Error>) -> Disposable?
}

extension Signal: BindingSourceProtocol { }

extension SignalProducer: BindingSourceProtocol {
	@discardableResult
	public func observe(_ observer: Observer<Value, Error>) -> Disposable? {
		var disposable: Disposable!

		startWithSignal { signal, signalDisposable in
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
	/// the binding should be teared down.
	var lifetime: Lifetime { get }

	/// Consume a value from the binding.
	func consume(_ value: Value)
}

/// Binds a signal to a target, updating the target's value to the latest
/// value sent by the signal.
///
/// - note: The binding will automatically terminate when the target is
///         deinitialized, or when the signal sends a `completed` event.
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
///   - signal: A signal to bind.
///
/// - returns: A disposable that can be used to terminate binding before the
///            deinitialization of the target or the signal's `completed`
///            event.
@discardableResult
public func <~
	<Target: BindingTargetProtocol, Source: BindingSourceProtocol>
	(target: Target, source: Source) -> Disposable?
	where Source.Value == Target.Value, Source.Error == NoError
{
	let disposable = source.observe(Observer(value: { [weak target] in target?.consume($0) }))
	if let disposable = disposable {
		target.lifetime.ended.observeCompleted { disposable.dispose() }
	}
	return disposable
}

/// Binds a source to a target, updating the target's value to the latest
/// value sent by the signal.
///
/// - note: The binding will automatically terminate when the target is
///         deinitialized, or when the signal sends a `completed` event.
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
///   - signal: A signal to bind.
///
/// - returns: A disposable that can be used to terminate binding before the
///            deinitialization of the target or the signal's `completed`
///            event.
@discardableResult
public func <~
	<Target: BindingTargetProtocol, Source: BindingSourceProtocol>
	(target: Target, source: Source) -> Disposable?
	where Target.Value: OptionalProtocol, Source.Value == Target.Value.Wrapped, Source.Error == NoError
{
	let disposable = source.observe(Observer(value: { [weak target] in target?.consume(Target.Value(reconstructing: $0)) }))
	if let disposable = disposable {
		target.lifetime.ended.observeCompleted { disposable.dispose() }
	}
	return disposable
}

/// A binding target that can be used with the `<~` operator.
public final class BindingTarget<Value>: BindingTargetProtocol {
	public let lifetime: Lifetime
	private let setter: (Value) -> Void

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

private let specificKey = DispatchSpecificKey<ObjectIdentifier>()
