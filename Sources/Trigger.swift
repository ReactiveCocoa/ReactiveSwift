import Foundation
import Result

/// A Trigger is a simple mechanism that can be used to when no explicit value is needed.
public final class Trigger: BindingSource, BindingTargetProvider {
	public typealias Value = ()
	public typealias Error = NoError
	
	let (lifetime, token) = Lifetime.make()
	let observer: Signal<Value, Error>.Observer
	/// A signal that sends `Void` whenever the trigger is fired.
	public var signal: Signal<Value, Error>
	
	public init() {
		(self.signal, self.observer) = Signal<Value, Error>.pipe()
	}
	
	public convenience init(capturing signal: Signal<Value, Error>) {
		self.init()
		lifetime += signal.observeValues(observer.send)
	}
	
	public convenience init<P: PropertyProtocol>(capturing property: P) where P.Value == Value {
		self.init(capturing: property.signal)
	}
	
	/// Fires the trigger.
	public func fire() {
		observer.send(value: ())
	}
	
	// MARK: BindingSource
	public var producer: SignalProducer<Value, Error> {
		return SignalProducer(signal)
	}
	// MARK: BindingTargetProvider
	public var bindingTarget: BindingTarget<Value> {
		return BindingTarget(lifetime: lifetime) { [weak self] in self?.fire() }
	}
}
