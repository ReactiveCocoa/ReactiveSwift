import Foundation
import enum Result.NoError

/// Represents a property that allows observation of its changes.
///
/// Only classes can conform to this protocol, because having a signal
/// for changes over time implies the origin must have a unique identity.
public protocol PropertyProtocol: class, BindingSource {
	associatedtype Value

	/// The current value of the property.
	var value: Value { get }

	/// The values producer of the property.
	///
	/// It produces a signal that sends the property's current value,
	/// followed by all changes over time. It completes when the property
	/// has deinitialized, or has no further change.
	///
	/// - note: If `self` is a composed property, the producer would be
	///         bound to the lifetime of its sources.
	var producer: SignalProducer<Value, NoError> { get }

	/// A signal that will send the property's changes over time. It
	/// completes when the property has deinitialized, or has no further
	/// change.
	///
	/// - note: If `self` is a composed property, the signal would be
	///         bound to the lifetime of its sources.
	var signal: Signal<Value, NoError> { get }
}

/// Represents an observable property that can be mutated directly.
public protocol MutablePropertyProtocol: PropertyProtocol, BindingTargetProvider {
	/// The current value of the property.
	var value: Value { get set }

	/// The lifetime of the property.
	var lifetime: Lifetime { get }
}

/// Default implementation of `BindingTargetProvider` for mutable properties.
extension MutablePropertyProtocol {
	public var bindingTarget: BindingTarget<Value> {
		return BindingTarget(lifetime: lifetime) { [weak self] in self?.value = $0 }
	}
}

/// Represents a mutable property that can be safety composed by exposing its
/// synchronization mechanic through the defined closure-based interface.
public protocol ComposableMutablePropertyProtocol: MutablePropertyProtocol {
	/// Atomically performs an arbitrary action using the current value of the
	/// variable.
	///
	/// - parameters:
	///   - action: A closure that accepts current property value.
	///
	/// - returns: the result of the action.
	func withValue<Result>(_ action: (Value) throws -> Result) rethrows -> Result

	/// Atomically modifies the variable.
	///
	/// - parameters:
	///   - action: A closure that accepts old property value and returns a new
	///             property value.
	///
	/// - returns: The result of the action.
	func modify<Result>(_ action: (inout Value) throws -> Result) rethrows -> Result
}

/// A read-only property that can be observed for its changes over time. There
/// are three categories of read-only properties:
///
/// # Constant property
/// Created by `Property(value:)`, the producer and signal of a constant
/// property would complete immediately when it is initialized.
///
/// # Existential property
/// Created by `Property(capturing:)`, it wraps any arbitrary `PropertyProtocol`
/// types, and passes through the behavior. Note that it would retain the
/// wrapped property.
///
/// Existential property would be deprecated when generalized existential
/// eventually lands in Swift.
///
/// # Composed property
/// A composed property presents a composed view of its sources, which can be
/// one or more properties, a producer, or a signal. It can be created using
/// property composition operators, `Property(_:)` or `Property(initial:then:)`.
///
/// It does not own its lifetime, and its producer and signal are bound to the
/// lifetime of its sources. It also does not have an influence on its sources,
/// so retaining a composed property would not prevent its sources from
/// deinitializing.
///
/// Note that composed properties do not retain any of its sources.
public final class Property<Value>: PropertyProtocol {
	private let disposable: Disposable?

	private let _value: () -> Value
	private let _producer: () -> SignalProducer<Value, NoError>
	private let _signal: () -> Signal<Value, NoError>

	/// The current value of the property.
	public var value: Value {
		return _value()
	}

	/// A producer for Signals that will send the property's current
	/// value, followed by all changes over time, then complete when the
	/// property has deinitialized or has no further changes.
	///
	/// - note: If `self` is a composed property, the producer would be
	///         bound to the lifetime of its sources.
	public var producer: SignalProducer<Value, NoError> {
		return _producer()
	}

	/// A signal that will send the property's changes over time, then
	/// complete when the property has deinitialized or has no further changes.
	///
	/// - note: If `self` is a composed property, the signal would be
	///         bound to the lifetime of its sources.
	public var signal: Signal<Value, NoError> {
		return _signal()
	}

	/// Initializes a constant property.
	///
	/// - parameters:
	///   - property: A value of the constant property.
	public init(value: Value) {
		disposable = nil
		_value = { value }
		_producer = { SignalProducer(value: value) }
		_signal = { Signal<Value, NoError>.empty }
	}

	/// Initializes an existential property which wraps the given property.
	///
	/// - note: The resulting property retains the given property.
	///
	/// - parameters:
	///   - property: A property to be wrapped.
	public init<P: PropertyProtocol>(capturing property: P) where P.Value == Value {
		disposable = nil
		_value = { property.value }
		_producer = { property.producer }
		_signal = { property.signal }
	}

	/// Initializes a composed property which reflects the given property.
	///
	/// - note: The resulting property does not retain the given property.
	///
	/// - parameters:
	///   - property: A property to be wrapped.
	public convenience init<P: PropertyProtocol>(_ property: P) where P.Value == Value {
		self.init(unsafeProducer: property.producer)
	}

	/// Initializes a composed property that first takes on `initial`, then each
	/// value sent on a signal created by `producer`.
	///
	/// - parameters:
	///   - initial: Starting value for the property.
	///   - values: A producer that will start immediately and send values to
	///             the property.
	public convenience init(initial: Value, then values: SignalProducer<Value, NoError>) {
		self.init(unsafeProducer: SignalProducer { observer, disposables in
			observer.send(value: initial)
			disposables += values.start(Signal.Observer(mappingInterruptedToCompleted: observer))
		})
	}

	/// Initialize a composed property that first takes on `initial`, then each
	/// value sent on `signal`.
	///
	/// - parameters:
	///   - initialValue: Starting value for the property.
	///   - values: A signal that will send values to the property.
	public convenience init(initial: Value, then values: Signal<Value, NoError>) {
		self.init(initial: initial, then: SignalProducer(values))
	}

	/// Initialize a composed property from a producer that promises to send
	/// at least one value synchronously in its start handler before sending any
	/// subsequent event.
	///
	/// - important: The producer and the signal of the created property would
	///              complete only when the `unsafeProducer` completes.
	///
	/// - warning: If the producer fails its promise, a fatal error would be
	///            raised.
	///
	/// - parameters:
	///   - unsafeProducer: The composed producer for creating the property.
	internal init(unsafeProducer: SignalProducer<Value, NoError>) {
		// Share a replayed producer with `self.producer` and `self.signal` so
		// they see a consistent view of the `self.value`.
		// https://github.com/ReactiveCocoa/ReactiveCocoa/pull/3042
		let producer = unsafeProducer.replayLazily(upTo: 1)

		let atomic = Atomic<Value?>(nil)
		disposable = producer.startWithValues { atomic.value = $0 }

		// Verify that an initial is sent. This is friendlier than deadlocking
		// in the event that one isn't.
		guard atomic.value != nil else {
			fatalError("A producer promised to send at least one value. Received none.")
		}

		_value = { atomic.value! }
		_producer = { producer }
		_signal = { producer.startAndRetrieveSignal() }
	}

	deinit {
		disposable?.dispose()
	}
}

/// A mutable property of type `Value` that allows observation of its changes.
///
/// Instances of this class are thread-safe.
public final class MutableProperty<Value>: ComposableMutablePropertyProtocol {
	private let token: Lifetime.Token
	private let observer: Signal<Value, NoError>.Observer
	private let atomic: RecursiveAtomic<Value>

	/// The current value of the property.
	///
	/// Setting this to a new value will notify all observers of `signal`, or
	/// signals created using `producer`.
	public var value: Value {
		get {
			return atomic.withValue { $0 }
		}

		set {
			swap(newValue)
		}
	}

	/// The lifetime of the property.
	public let lifetime: Lifetime

	/// A signal that will send the property's changes over time,
	/// then complete when the property has deinitialized.
	public let signal: Signal<Value, NoError>

	/// A producer for Signals that will send the property's current value,
	/// followed by all changes over time, then complete when the property has
	/// deinitialized.
	public var producer: SignalProducer<Value, NoError> {
		return SignalProducer { [atomic, signal] producerObserver, producerDisposable in
			atomic.withValue { value in
				producerObserver.send(value: value)
				producerDisposable += signal.observe(Signal.Observer(mappingInterruptedToCompleted: producerObserver))
			}
		}
	}

	/// Initializes a mutable property that first takes on `initialValue`
	///
	/// - parameters:
	///   - initialValue: Starting value for the mutable property.
	public init(_ initialValue: Value) {
		(signal, observer) = Signal.pipe()
		token = Lifetime.Token()
		lifetime = Lifetime(token)

		/// Need a recursive lock around `value` to allow recursive access to
		/// `value`. Note that recursive sets will still deadlock because the
		/// underlying producer prevents sending recursive events.
		atomic = RecursiveAtomic(initialValue,
		                          name: "org.reactivecocoa.ReactiveSwift.MutableProperty",
		                          didSet: observer.send(value:))
	}

	/// Atomically replaces the contents of the variable.
	///
	/// - parameters:
	///   - newValue: New property value.
	///
	/// - returns: The previous property value.
	@discardableResult
	public func swap(_ newValue: Value) -> Value {
		return atomic.swap(newValue)
	}

	/// Atomically modifies the variable.
	///
	/// - parameters:
	///   - action: A closure that accepts old property value and returns a new
	///             property value.
	///
	/// - returns: The result of the action.
	@discardableResult
	public func modify<Result>(_ action: (inout Value) throws -> Result) rethrows -> Result {
		return try atomic.modify(action)
	}

	/// Atomically performs an arbitrary action using the current value of the
	/// variable.
	///
	/// - parameters:
	///   - action: A closure that accepts current property value.
	///
	/// - returns: the result of the action.
	@discardableResult
	public func withValue<Result>(_ action: (Value) throws -> Result) rethrows -> Result {
		return try atomic.withValue(action)
	}

	deinit {
		observer.sendCompleted()
	}
}
