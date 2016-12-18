import Foundation
import enum Result.NoError

/// Represents a property that allows observation of its changes.
///
/// Only classes can conform to this protocol, because having a signal
/// for changes over time implies the origin must have a unique identity.
///
/// A conforming type must:
/// 1. ensure that the latest value is always visible before any observer is
///    notified.
///
/// If a conforming type intends to serialize its getter and setter accesses, it
/// must also:
/// 1. support reentrancy;
/// 2. ensure the observer call-out happens in the same protected section as the
///    setter.
/// 3. ensure the closures supplied to `withValue(_:)` are invoked synchronously
///    with the protection of its synchronoization mechanism.
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

	/// Perform an arbitrary action on the current value of the property.
	/// Serialized properties should invoke `body` in its protected section.
	func withValue<R>(_ body: (Value) throws -> R) rethrows -> R
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

// Note on property composition operators:
//
// As the Property contract requires reentrancy, the order of invocation of
// `withValue` is insignificant and should not lead to deadlocks.

/// Protocol composition operators
///
/// The producer and the signal of transformed properties would complete
/// only when its source properties have deinitialized.
///
/// A composed property would retain its ultimate source, but not
/// any intermediate property during the composition.
extension PropertyProtocol {
	/// Lifts a unary stateful SignalProducer operator to operate upon
	/// PropertyProtocol instead.
	fileprivate func lift<U>(_ transform: @escaping (SignalProducer<Value, NoError>) -> SignalProducer<U, NoError>) -> Property<U> {
		return Property(unsafeValues: transform(self.values))
	}

	/// Lifts a binary stateful SignalProducer operator to operate upon
	/// PropertyProtocol instead.
	fileprivate func lift<P: PropertyProtocol, U>(_ transform: @escaping (SignalProducer<Value, NoError>) -> (SignalProducer<P.Value, NoError>) -> SignalProducer<U, NoError>) -> (P) -> Property<U> {
		return { other in
			return Property(unsafeValues: transform(self.values)(other.values))
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
		return self.withValue { value in
			return Property<U>(initial: transform(value),
			                   then: self.signal.map(transform))
		}
	}

	/// Create a property which forwards all events of `self` onto the given
	/// scheduler, instead of whichever scheduler they originally arrived upon.
	///
	/// - parameters:
	///   - scheduler: A scheduler to deliver events on.
	///
	/// - returns: A property that forwards all events on the given scheduler.
	public func observe(on scheduler: SchedulerProtocol) -> Property<Value> {
		return self.withValue { value in
			return Property(initial: value,
			                then: self.signal.observe(on: scheduler),
			                producerTransform: { $0.start(on: scheduler) })
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
		return self.withValue { value in
			return other.withValue { otherValue in
				return Property(initial: (value, otherValue),
				                then: self.signal.zip(with: other.signal))
			}
		}
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
	private let box: PropertyBoxBase<Value>

	/// The current value of the property.
	public var value: Value {
		return _value()
	}

	/// A producer for Signals that will send the property's current
	/// value, followed by all changes over time, then complete when the
	/// property has deinitialized or has no further changes.
	public let producer: SignalProducer<Value, NoError>

	/// A signal that will send the property's changes over time, then
	/// complete when the property has deinitialized or has no further changes.
	public let signal: Signal<Value, NoError>

	/// Initializes a constant property.
	///
	/// - parameters:
	///   - property: A value of the constant property.
	public init(value: Value) {
		disposable = nil
		_value = { value }
		producer = SignalProducer(value: value)
		signal = .empty
		box = PropertyBox<Property<Value>>(constant: value)
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
		producer = property.producer
		signal = property.signal
		box = PropertyBox(property)
	}

	/// Initializes a composed property which reflects the given property.
	///
	/// - note: The resulting property does not retain the given property.
	///
	/// - parameters:
	///   - property: A property to be wrapped.
	public convenience init<P: PropertyProtocol>(_ property: P) where P.Value == Value {
		self.init(unsafeValues: property.producer)
	}

	/// Initializes a composed property that first takes on `initial`, then each
	/// value sent on a signal created by `producer`.
	///
	/// - parameters:
	///   - initial: Starting value for the property.
	///   - values: A producer that will start immediately and send values to
	///             the property.
	public convenience init(initial: Value, then values: SignalProducer<Value, NoError>) {
		self.init(unsafeValues: values.prefix(value: initial))
	}

	/// Initialize a composed property that first takes on `initial`, then each
	/// value sent on `signal`.
	///
	/// - parameters:
	///   - initialValue: Starting value for the property.
	///   - values: A signal that will send values to the property.
	public convenience init(initial: Value, then values: Signal<Value, NoError>) {
		self.init(initial: initial, then: values, producerTransform: { $0 })
	}

	fileprivate init(
		unsafeValues: SignalProducer<Value, NoError>,
		producerTransform: (SignalProducer<Value, NoError>) -> SignalProducer<Value, NoError> = { $0 }
	) {
		let cache = RecursiveAtomic<Value?>(nil)

		var propertySignal: Signal<Value, Error>!
		var d: Disposable!

		let replay = unsafeValues.replayLazily(upTo: 1)

		replay.startWithSignal { signal, _ in
			d = signal.observeValues { cache.value = $0 }
			propertySignal = signal
		}

		guard cache.value != nil else {
			fatalError("Expected a value being synchronously sent. Got none.")
		}

		_value = { cache.value! }
		producer = producerTransform(replay)
		signal = propertySignal
		box = PropertyBox<Property<Value>>(cache)
		disposable = d
	}

	fileprivate convenience init(
		initial: Value,
		then values: Signal<Value, NoError>,
		producerTransform: (SignalProducer<Value, NoError>) -> SignalProducer<Value, NoError>
	) {
		let producer = SignalProducer<Value, NoError> { observer, disposable in
			observer.send(value: initial)
			disposable += values.propertyObserve(observer)
		}

		self.init(unsafeValues: producer, producerTransform: producerTransform)
	}

	public func withValue<R>(_ body: (Value) throws -> R) rethrows -> R {
		return try box.withValue(body)
	}

	deinit {
		disposable?.dispose()
	}
}

extension PropertyProtocol {
	internal var values: SignalProducer<Value, NoError> {
		return SignalProducer { observer, disposable in
			self.withValue { value in
				observer.send(value: value)
				disposable += self.signal.propertyObserve(observer)
			}
		}
	}
}

extension SignalProtocol {
	/// `observe` for property composition. It turns `interrupted` into
	/// `completed`, and traps on `failed`.
	@discardableResult
	internal func propertyObserve(_ observer: Observer<Value, Error>) -> Disposable? {
		return observe { event in
			switch event {
			case .value, .completed:
				observer.action(event)

			case .interrupted:
				observer.sendCompleted()

			case let .failed(error):
				fatalError("Received `failed` event in a `Property` which should never fail. \(error)")
			}
		}
	}
}

private final class Box<Value> {
	let value: Value

	init(_ value: Value) {
		self.value = value
	}
}

// The existential box for `PropertyProtocol.withValue`.
private class PropertyBox<P: PropertyProtocol>: PropertyBoxBase<P.Value> {
	private let base: PropertyBoxBacking<P>

	fileprivate init(_ base: P) {
		self.base = .property(base)
	}

	fileprivate init(_ atomic: RecursiveAtomic<P.Value?>) {
		self.base = .composed(atomic)
	}

	fileprivate init(_ atomic: RecursiveAtomic<P.Value>) {
		self.base = .composedStateless(atomic)
	}

	fileprivate init(constant: P.Value) {
		self.base = .constant(constant)
	}

	fileprivate override func withValue<R>(_ body: (P.Value) throws -> R) rethrows -> R {
		switch base {
		case let .constant(value):
			return try body(value)

		case let .composed(atomic):
			return try atomic.withValue { try body($0!) }

		case let .composedStateless(atomic):
			return try atomic.withValue(body)

		case let .property(property):
			return try property.withValue(body)
		}
	}
}

// The base class of the existential box.
private class PropertyBoxBase<Value> {
	fileprivate func withValue<R>(_ body: (Value) throws -> R) rethrows -> R {
		fatalError("This method should have been overriden.")
	}
}

// The backing the existential box.
private enum PropertyBoxBacking<P: PropertyProtocol> {
	case constant(P.Value)
	case composed(RecursiveAtomic<P.Value?>)
	case composedStateless(RecursiveAtomic<P.Value>)
	case property(P)
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
	///   - body: A closure that accepts old property value and returns a new
	///           property value.
	///
	/// - returns: The result of the closure.
	@discardableResult
	public func modify<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
		return try atomic.modify(body)
	}

	/// Atomically performs an arbitrary action using the current value of the
	/// variable.
	///
	/// - parameters:
	///   - body: A closure that accepts current property value.
	///
	/// - returns: the result of the closure.
	@discardableResult
	public func withValue<Result>(_ body: (Value) throws -> Result) rethrows -> Result {
		return try atomic.withValue(body)
	}

	deinit {
		observer.sendCompleted()
	}
}
