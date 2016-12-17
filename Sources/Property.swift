import Foundation
import enum Result.NoError

/// Represents a property that allows observation of its changes.
///
/// Only classes can conform to this protocol, because having a signal
/// for changes over time implies the origin must have a unique identity.
public protocol PropertyProtocol: class, BindingSourceProtocol {
	associatedtype Value

	/// The current value of the property.
	var value: Value { get }

	/// The values producer of the property.
	///
	/// It produces a signal that sends the property's current value,
	/// followed by all changes over time. It completes when the property
	/// has deinitialized, or has no further change.
	var producer: SignalProducer<Value, NoError> { get }

	/// A signal that will send the property's changes over time. It
	/// completes when the property has deinitialized, or has no further
	/// change.
	var signal: Signal<Value, NoError> { get }
}

extension PropertyProtocol {
	@discardableResult
	public func observe(_ observer: Observer<Value, NoError>) -> Disposable? {
		return producer.observe(observer)
	}
}

/// Represents an observable property that can be mutated directly.
public protocol MutablePropertyProtocol: PropertyProtocol, BindingTargetProtocol {
	/// The current value of the property.
	var value: Value { get set }
}

/// Default implementation of `MutablePropertyProtocol` for `BindingTarget`.
extension MutablePropertyProtocol {
	public func consume(_ value: Value) {
		self.value = value
	}
}

/// Protocol composition operators
///
/// The producer and the signal of transformed properties would complete
/// only when its source properties have deinitialized.
///
/// A composed property would retain its ultimate source, but not
/// any intermediate property during the composition.
extension PropertyProtocol {
	/// Lifts a unary SignalProducer operator to operate upon PropertyProtocol
	/// instead.
	///
	/// - parameters:
	///   - transform: A unary `SignalProducer` transform to apply on `self`.
	fileprivate func lift<U>(_ transform: @escaping (SignalProducer<Value, NoError>) -> SignalProducer<U, NoError>) -> Property<U> {
		return Property(unsafeProducer: transform(self.producer))
	}

	/// Lifts a binary SignalProducer operator to operate upon PropertyProtocol
	/// instead.
	///
	/// - parameters:
	///   - transform: A binary `SignalProducer` operator.
	fileprivate func lift<P: PropertyProtocol, U>(_ transform: @escaping (SignalProducer<Value, NoError>) -> (SignalProducer<P.Value, NoError>) -> SignalProducer<U, NoError>) -> (P) -> Property<U> {
		return { otherProperty in
			return Property(unsafeProducer: transform(self.producer)(otherProperty.producer))
		}
	}

	/// Maps the current value and all subsequent values to a new property.
	///
	/// - parameters:
	///   - transform: A closure that will map the current `value` of this
	///                `Property` to a new value.
	///
	/// - returns: A new instance of `AnyProperty` who's holds a mapped value
	///            from `self`.
	public func map<U>(_ transform: @escaping (Value) -> U) -> Property<U> {
		return lift { $0.map(transform) }
	}

	/// Create a property which forwards all changes and deinitialization of
	/// `self` onto the given scheduler, instead of whichever scheduler they
	/// originally arrived upon.
	///
	/// - note: The producer of the resulting property would replay the current
	///         value synchronously. If the initial value has to be delivered on
	///         the given scheduler, `start(on:)` must be applied to the producer.
	///
	/// - parameters:
	///   - scheduler: A scheduler to deliver events on.
	///
	/// - returns: A property that forwards all events on the given scheduler.
	public func observe(on scheduler: SchedulerProtocol) -> Property<Value> {
		return lift { producer in
			return SignalProducer { observer, disposable in
				var hasReceivedFirst = false

				disposable += producer.start { event in
					if hasReceivedFirst {
						// It is unnecessary to add the scheduler token to the producer
						// disposable (which would need `SerialDisposable` to minimize
						// the memory consumption), as the event emitter would block post-
						// termination events anyway.
						scheduler.schedule {
							observer.action(event)
						}
					} else {
						hasReceivedFirst = true
						observer.action(event)
					}
				}
			}
		}
	}

	/// Combines the current value and the subsequent values of two `Property`s in
	/// the manner described by `Signal.combineLatestWith:`.
	///
	/// - parameters:
	///   - other: A property to combine `self`'s value with.
	///
	/// - returns: A property that holds a tuple containing values of `self` and
	///            the given property.
	public func combineLatest<P: PropertyProtocol>(with other: P) -> Property<(Value, P.Value)> {
		return lift(SignalProducer.combineLatest(with:))(other)
	}

	/// Zips the current value and the subsequent values of two `Property`s in
	/// the manner described by `Signal.zipWith`.
	///
	/// - parameters:
	///   - other: A property to zip `self`'s value with.
	///
	/// - returns: A property that holds a tuple containing values of `self` and
	///            the given property.
	public func zip<P: PropertyProtocol>(with other: P) -> Property<(Value, P.Value)> {
		return lift(SignalProducer.zip(with:))(other)
	}

	/// Forward events from `self` with history: values of the returned property
	/// are a tuple whose first member is the previous value and whose second
	/// member is the current value. `initial` is supplied as the first member
	/// when `self` sends its first value.
	///
	/// - parameters:
	///   - initial: A value that will be combined with the first value sent by
	///              `self`.
	///
	/// - returns: A property that holds tuples that contain previous and
	///            current values of `self`.
	public func combinePrevious(_ initial: Value) -> Property<(Value, Value)> {
		return lift { $0.combinePrevious(initial) }
	}

	/// Forward only those values from `self` which do not pass `isRepeat` with
	/// respect to the previous value.
	///
	/// - parameters:
	///   - isRepeat: A predicate to determine if the two given values are equal.
	///
	/// - returns: A property that does not emit events for two equal values
	///            sequentially.
	public func skipRepeats(_ isRepeat: @escaping (Value, Value) -> Bool) -> Property<Value> {
		return lift { $0.skipRepeats(isRepeat) }
	}
}

extension PropertyProtocol where Value: Equatable {
	/// Forward only those values from `self` which do not pass `isRepeat` with
	/// respect to the previous value.
	///
	/// - returns: A property that does not emit events for two equal values
	///            sequentially.
	public func skipRepeats() -> Property<Value> {
		return lift { $0.skipRepeats() }
	}
}

extension PropertyProtocol where Value: PropertyProtocol {
	/// Flattens the inner property held by `self` (into a single property of
	/// values), according to the semantics of the given strategy.
	///
	/// - parameters:
	///   - strategy: The preferred flatten strategy.
	///
	/// - returns: A property that sends the values of its inner properties.
	public func flatten(_ strategy: FlattenStrategy) -> Property<Value.Value> {
		return lift { $0.flatMap(strategy) { $0.producer } }
	}
}

extension PropertyProtocol {
	/// Maps each property from `self` to a new property, then flattens the
	/// resulting properties (into a single property), according to the
	/// semantics of the given strategy.
	///
	/// - parameters:
	///   - strategy: The preferred flatten strategy.
	///   - transform: The transform to be applied on `self` before flattening.
	///
	/// - returns: A property that sends the values of its inner properties.
	public func flatMap<P: PropertyProtocol>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> P) -> Property<P.Value> {
		return lift { $0.flatMap(strategy) { transform($0).producer } }
	}

	/// Forward only those values from `self` that have unique identities across
	/// the set of all values that have been held.
	///
	/// - note: This causes the identities to be retained to check for 
	///         uniqueness.
	///
	/// - parameters:
	///   - transform: A closure that accepts a value and returns identity
	///                value.
	///
	/// - returns: A property that sends unique values during its lifetime.
	public func uniqueValues<Identity: Hashable>(_ transform: @escaping (Value) -> Identity) -> Property<Value> {
		return lift { $0.uniqueValues(transform) }
	}
}

extension PropertyProtocol where Value: Hashable {
	/// Forwards only those values from `self` that are unique across the set of
	/// all values that have been seen.
	///
	/// - note: This causes the identities to be retained to check for uniqueness.
	///         Providing a function that returns a unique value for each sent
	///         value can help you reduce the memory footprint.
	///
	/// - returns: A property that sends unique values during its lifetime.
	public func uniqueValues() -> Property<Value> {
		return lift { $0.uniqueValues() }
	}
}

extension PropertyProtocol {
	/// Combines the values of all the given properties, in the manner described
	/// by `combineLatest(with:)`.
	public static func combineLatest<A: PropertyProtocol, B: PropertyProtocol>(_ a: A, _ b: B) -> Property<(A.Value, B.Value)> where Value == A.Value {
		return a.combineLatest(with: b)
	}

	/// Combines the values of all the given properties, in the manner described
	/// by `combineLatest(with:)`.
	public static func combineLatest<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol>(_ a: A, _ b: B, _ c: C) -> Property<(A.Value, B.Value, C.Value)> where Value == A.Value {
		return combineLatest(a, b)
			.combineLatest(with: c)
			.map(repack)
	}

	/// Combines the values of all the given properties, in the manner described
	/// by `combineLatest(with:)`.
		public static func combineLatest<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D) -> Property<(A.Value, B.Value, C.Value, D.Value)> where Value == A.Value {
		return combineLatest(a, b, c)
			.combineLatest(with: d)
			.map(repack)
	}

	/// Combines the values of all the given properties, in the manner described
	/// by `combineLatest(with:)`.
		public static func combineLatest<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol, E: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E) -> Property<(A.Value, B.Value, C.Value, D.Value, E.Value)> where Value == A.Value {
		return combineLatest(a, b, c, d)
			.combineLatest(with: e)
			.map(repack)
	}

	/// Combines the values of all the given properties, in the manner described
	/// by `combineLatest(with:)`.
		public static func combineLatest<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol, E: PropertyProtocol, F: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F) -> Property<(A.Value, B.Value, C.Value, D.Value, E.Value, F.Value)> where Value == A.Value {
		return combineLatest(a, b, c, d, e)
			.combineLatest(with: f)
			.map(repack)
	}

	/// Combines the values of all the given properties, in the manner described
	/// by `combineLatest(with:)`.
		public static func combineLatest<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol, E: PropertyProtocol, F: PropertyProtocol, G: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G) -> Property<(A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value)> where Value == A.Value {
		return combineLatest(a, b, c, d, e, f)
			.combineLatest(with: g)
			.map(repack)
	}

	/// Combines the values of all the given properties, in the manner described
	/// by `combineLatest(with:)`.
		public static func combineLatest<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol, E: PropertyProtocol, F: PropertyProtocol, G: PropertyProtocol, H: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H) -> Property<(A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value)> where Value == A.Value {
		return combineLatest(a, b, c, d, e, f, g)
			.combineLatest(with: h)
			.map(repack)
	}

	/// Combines the values of all the given properties, in the manner described
	/// by `combineLatest(with:)`.
		public static func combineLatest<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol, E: PropertyProtocol, F: PropertyProtocol, G: PropertyProtocol, H: PropertyProtocol, I: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H, _ i: I) -> Property<(A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value, I.Value)> where Value == A.Value {
		return combineLatest(a, b, c, d, e, f, g, h)
			.combineLatest(with: i)
			.map(repack)
	}

	/// Combines the values of all the given properties, in the manner described
	/// by `combineLatest(with:)`.
		public static func combineLatest<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol, E: PropertyProtocol, F: PropertyProtocol, G: PropertyProtocol, H: PropertyProtocol, I: PropertyProtocol, J: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H, _ i: I, _ j: J) -> Property<(A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value, I.Value, J.Value)> where Value == A.Value {
		return combineLatest(a, b, c, d, e, f, g, h, i)
			.combineLatest(with: j)
			.map(repack)
	}

	/// Combines the values of all the given producers, in the manner described by
	/// `combineLatest(with:)`. Returns nil if the sequence is empty.
	public static func combineLatest<S: Sequence>(_ properties: S) -> Property<[S.Iterator.Element.Value]>? where S.Iterator.Element: PropertyProtocol {
		var generator = properties.makeIterator()
		if let first = generator.next() {
			let initial = first.map { [$0] }
			return IteratorSequence(generator).reduce(initial) { property, next in
				property.combineLatest(with: next).map { $0.0 + [$0.1] }
			}
		}

		return nil
	}

	/// Zips the values of all the given properties, in the manner described by
	/// `zip(with:)`.
	public static func zip<A: PropertyProtocol, B: PropertyProtocol>(_ a: A, _ b: B) -> Property<(A.Value, B.Value)> where Value == A.Value {
		return a.zip(with: b)
	}

	/// Zips the values of all the given properties, in the manner described by
	/// `zip(with:)`.
	public static func zip<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol>(_ a: A, _ b: B, _ c: C) -> Property<(A.Value, B.Value, C.Value)> where Value == A.Value {
		return zip(a, b)
			.zip(with: c)
			.map(repack)
	}

	/// Zips the values of all the given properties, in the manner described by
	/// `zip(with:)`.
	public static func zip<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D) -> Property<(A.Value, B.Value, C.Value, D.Value)> where Value == A.Value {
		return zip(a, b, c)
			.zip(with: d)
			.map(repack)
	}

	/// Zips the values of all the given properties, in the manner described by
	/// `zip(with:)`.
	public static func zip<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol, E: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E) -> Property<(A.Value, B.Value, C.Value, D.Value, E.Value)> where Value == A.Value {
		return zip(a, b, c, d)
			.zip(with: e)
			.map(repack)
	}

	/// Zips the values of all the given properties, in the manner described by
	/// `zip(with:)`.
	public static func zip<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol, E: PropertyProtocol, F: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F) -> Property<(A.Value, B.Value, C.Value, D.Value, E.Value, F.Value)> where Value == A.Value {
		return zip(a, b, c, d, e)
			.zip(with: f)
			.map(repack)
	}

	/// Zips the values of all the given properties, in the manner described by
	/// `zip(with:)`.
	public static func zip<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol, E: PropertyProtocol, F: PropertyProtocol, G: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G) -> Property<(A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value)> where Value == A.Value {
		return zip(a, b, c, d, e, f)
			.zip(with: g)
			.map(repack)
	}

	/// Zips the values of all the given properties, in the manner described by
	/// `zip(with:)`.
	public static func zip<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol, E: PropertyProtocol, F: PropertyProtocol, G: PropertyProtocol, H: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H) -> Property<(A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value)> where Value == A.Value {
		return zip(a, b, c, d, e, f, g)
			.zip(with: h)
			.map(repack)
	}

	/// Zips the values of all the given properties, in the manner described by
	/// `zip(with:)`.
	public static func zip<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol, E: PropertyProtocol, F: PropertyProtocol, G: PropertyProtocol, H: PropertyProtocol, I: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H, _ i: I) -> Property<(A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value, I.Value)> where Value == A.Value {
		return zip(a, b, c, d, e, f, g, h)
			.zip(with: i)
			.map(repack)
	}

	/// Zips the values of all the given properties, in the manner described by
	/// `zip(with:)`.
	public static func zip<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol, E: PropertyProtocol, F: PropertyProtocol, G: PropertyProtocol, H: PropertyProtocol, I: PropertyProtocol, J: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H, _ i: I, _ j: J) -> Property<(A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value, I.Value, J.Value)> where Value == A.Value {
		return zip(a, b, c, d, e, f, g, h, i)
			.zip(with: j)
			.map(repack)
	}

	/// Zips the values of all the given properties, in the manner described by
	/// `zip(with:)`. Returns nil if the sequence is empty.
	public static func zip<S: Sequence>(_ properties: S) -> Property<[S.Iterator.Element.Value]>? where S.Iterator.Element: PropertyProtocol {
		var generator = properties.makeIterator()
		if let first = generator.next() {
			let initial = first.map { [$0] }
			return IteratorSequence(generator).reduce(initial) { property, next in
				property.zip(with: next).map { $0.0 + [$0.1] }
			}
		}
		
		return nil
	}
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
/// It respects and have no effect on the lifetime of its root sources. In other
/// words, the producer and signal of a composed property could complete before
/// or outlive the composed property, depending on its sources and the
/// composition.
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
	public var producer: SignalProducer<Value, NoError> {
		return _producer()
	}

	/// A signal that will send the property's changes over time, then
	/// complete when the property has deinitialized or has no further changes.
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
		self.init(unsafeProducer: values.prefix(value: initial))
	}

	/// Initialize a composed property that first takes on `initial`, then each
	/// value sent on `signal`.
	///
	/// - parameters:
	///   - initialValue: Starting value for the property.
	///   - values: A signal that will send values to the property.
	public convenience init(initial: Value, then values: Signal<Value, NoError>) {
		self.init(unsafeProducer: SignalProducer(values).prefix(value: initial))
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
	fileprivate init(unsafeProducer: SignalProducer<Value, NoError>) {
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
public final class MutableProperty<Value>: MutablePropertyProtocol {
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
		return SignalProducer { [atomic, weak self] producerObserver, producerDisposable in
			atomic.withValue { value in
				if let strongSelf = self {
					producerObserver.send(value: value)
					producerDisposable += strongSelf.signal.observe(producerObserver)
				} else {
					producerObserver.send(value: value)
					producerObserver.sendCompleted()
				}
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
	public func withValue<Result>(action: (Value) throws -> Result) rethrows -> Result {
		return try atomic.withValue(action)
	}

	deinit {
		observer.sendCompleted()
	}
}
