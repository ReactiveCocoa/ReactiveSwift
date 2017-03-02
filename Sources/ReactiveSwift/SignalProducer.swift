import Dispatch
import Foundation
import Result

/// A SignalProducer creates Signals that can produce values of type `Value` 
/// and/or fail with errors of type `Error`. If no failure should be possible, 
/// `NoError` can be specified for `Error`.
///
/// SignalProducers can be used to represent operations or tasks, like network
/// requests, where each invocation of `start()` will create a new underlying
/// operation. This ensures that consumers will receive the results, versus a
/// plain Signal, where the results might be sent before any observers are
/// attached.
///
/// Because of the behavior of `start()`, different Signals created from the
/// producer may see a different version of Events. The Events may arrive in a
/// different order between Signals, or the stream might be completely
/// different!
public struct SignalProducer<Value, Error: Swift.Error> {
	public typealias ProducedSignal = Signal<Value, Error>

	private let startHandler: (Signal<Value, Error>.Observer, CompositeDisposable) -> Void

	/// Initializes a `SignalProducer` that will emit the same events as the
	/// given signal.
	///
	/// If the Disposable returned from `start()` is disposed or a terminating
	/// event is sent to the observer, the given signal will be disposed.
	///
	/// - parameters:
	///   - signal: A signal to observe after starting the producer.
	public init<S: SignalProtocol>(_ signal: S) where S.Value == Value, S.Error == Error {
		self.init { observer, disposable in
			disposable += signal.observe(observer)
		}
	}

	/// Initializes a SignalProducer that will invoke the given closure once for
	/// each invocation of `start()`.
	///
	/// The events that the closure puts into the given observer will become
	/// the events sent by the started `Signal` to its observers.
	///
	/// - note: If the `Disposable` returned from `start()` is disposed or a
	///         terminating event is sent to the observer, the given
	///         `CompositeDisposable` will be disposed, at which point work
	///         should be interrupted and any temporary resources cleaned up.
	///
	/// - parameters:
	///   - startHandler: A closure that accepts observer and a disposable.
	public init(_ startHandler: @escaping (Signal<Value, Error>.Observer, CompositeDisposable) -> Void) {
		self.startHandler = startHandler
	}

	/// Creates a producer for a `Signal` that will immediately send one value
	/// then complete.
	///
	/// - parameters:
	///   - value: A value that should be sent by the `Signal` in a `value`
	///            event.
	public init(value: Value) {
		self.init { observer, disposable in
			observer.send(value: value)
			observer.sendCompleted()
		}
	}

	/// Creates a producer for a `Signal` that immediately sends one value, then
	/// completes.
	///
	/// This initializer differs from `init(value:)` in that its sole `value`
	/// event is constructed lazily by invoking the supplied `action` when
	/// the `SignalProducer` is started.
	///
	/// - parameters:
	///   - action: A action that yields a value to be sent by the `Signal` as
	///             a `value` event.
	public init(_ action: @escaping () -> Value) {
		self.init { observer, disposable in
			observer.send(value: action())
			observer.sendCompleted()
		}
	}

	/// Creates a producer for a `Signal` that will immediately fail with the
	/// given error.
	///
	/// - parameters:
	///   - error: An error that should be sent by the `Signal` in a `failed`
	///            event.
	public init(error: Error) {
		self.init { observer, disposable in
			observer.send(error: error)
		}
	}

	/// Creates a producer for a Signal that will immediately send one value
	/// then complete, or immediately fail, depending on the given Result.
	///
	/// - parameters:
	///   - result: A `Result` instance that will send either `value` event if
	///             `result` is `success`ful or `failed` event if `result` is a
	///             `failure`.
	public init(result: Result<Value, Error>) {
		switch result {
		case let .success(value):
			self.init(value: value)

		case let .failure(error):
			self.init(error: error)
		}
	}

	/// Creates a producer for a Signal that will immediately send the values
	/// from the given sequence, then complete.
	///
	/// - parameters:
	///   - values: A sequence of values that a `Signal` will send as separate
	///             `value` events and then complete.
	public init<S: Sequence>(_ values: S) where S.Iterator.Element == Value {
		self.init { observer, disposable in
			for value in values {
				observer.send(value: value)

				if disposable.isDisposed {
					break
				}
			}

			observer.sendCompleted()
		}
	}
	
	/// Creates a producer for a Signal that will immediately send the values
	/// from the given sequence, then complete.
	///
	/// - parameters:
	///   - first: First value for the `Signal` to send.
	///   - second: Second value for the `Signal` to send.
	///   - tail: Rest of the values to be sent by the `Signal`.
	public init(values first: Value, _ second: Value, _ tail: Value...) {
		self.init([ first, second ] + tail)
	}

	/// A producer for a Signal that will immediately complete without sending
	/// any values.
	public static var empty: SignalProducer {
		return self.init { observer, disposable in
			observer.sendCompleted()
		}
	}

	/// A producer for a Signal that never sends any events to its observers.
	public static var never: SignalProducer {
		return self.init { _ in return }
	}

	/// Create a Signal from the producer, pass it into the given closure,
	/// then start sending events on the Signal when the closure has returned.
	///
	/// The closure will also receive a disposable which can be used to
	/// interrupt the work associated with the signal and immediately send an
	/// `interrupted` event.
	///
	/// - parameters:
	///   - setUp: A closure that accepts a `signal` and `interrupter`.
	public func startWithSignal(_ setup: (_ signal: Signal<Value, Error>, _ interrupter: Disposable) -> Void) {
		// Disposes of the work associated with the SignalProducer and any
		// upstream producers.
		let producerDisposable = CompositeDisposable()

		let (signal, observer) = Signal<Value, Error>.pipe(disposable: producerDisposable)

		// Directly disposed of when `start()` or `startWithSignal()` is
		// disposed.
		let cancelDisposable = ActionDisposable(action: observer.sendInterrupted)

		setup(signal, cancelDisposable)

		if cancelDisposable.isDisposed {
			return
		}

		startHandler(observer, producerDisposable)
	}
}

/// A protocol used to constraint `SignalProducer` operators.
public protocol SignalProducerProtocol {
	/// The type of values being sent on the producer
	associatedtype Value
	/// The type of error that can occur on the producer. If errors aren't possible
	/// then `NoError` can be used.
	associatedtype Error: Swift.Error

	/// Extracts a signal producer from the receiver.
	var producer: SignalProducer<Value, Error> { get }

	/// Initialize a signal
	init(_ startHandler: @escaping (Signal<Value, Error>.Observer, CompositeDisposable) -> Void)

	/// Creates a Signal from the producer, passes it into the given closure,
	/// then starts sending events on the Signal when the closure has returned.
	func startWithSignal(_ setup: (_ signal: Signal<Value, Error>, _ interrupter: Disposable) -> Void)
}

extension SignalProducer: SignalProducerProtocol {
	public var producer: SignalProducer {
		return self
	}
}

extension SignalProducerProtocol {
	/// Create a Signal from the producer, then attach the given observer to
	/// the `Signal` as an observer.
	///
	/// - parameters:
	///   - observer: An observer to attach to produced signal.
	///
	/// - returns: A `Disposable` which can be used to interrupt the work
	///            associated with the signal and immediately send an
	///            `interrupted` event.
	@discardableResult
	public func start(_ observer: Signal<Value, Error>.Observer = .init()) -> Disposable {
		var disposable: Disposable!

		startWithSignal { signal, innerDisposable in
			signal.observe(observer)
			disposable = innerDisposable
		}

		return disposable
	}

	/// Convenience override for start(_:) to allow trailing-closure style
	/// invocations.
	///
	/// - parameters:
	///   - observerAction: A closure that accepts `Event` sent by the produced
	///                     signal.
	///
	/// - returns: A `Disposable` which can be used to interrupt the work
	///            associated with the signal and immediately send an
	///            `interrupted` event.
	@discardableResult
	public func start(_ observerAction: @escaping Signal<Value, Error>.Observer.Action) -> Disposable {
		return start(Observer(observerAction))
	}

	/// Create a Signal from the producer, then add an observer to the `Signal`,
	/// which will invoke the given callback when `value` or `failed` events are
	/// received.
	///
	/// - parameters:
	///   - result: A closure that accepts a `result` that contains a `.success`
	///             case for `value` events or `.failure` case for `failed` event.
	///
	/// - returns:  A Disposable which can be used to interrupt the work
	///             associated with the Signal, and prevent any future callbacks
	///             from being invoked.
	@discardableResult
	public func startWithResult(_ result: @escaping (Result<Value, Error>) -> Void) -> Disposable {
		return start(
			Observer(
				value: { result(.success($0)) },
				failed: { result(.failure($0)) }
			)
		)
	}

	/// Create a Signal from the producer, then add exactly one observer to the
	/// Signal, which will invoke the given callback when a `completed` event is
	/// received.
	///
	/// - parameters:
	///   - completed: A closure that will be envoked when produced signal sends
	///                `completed` event.
	///
	/// - returns: A `Disposable` which can be used to interrupt the work
	///            associated with the signal.
	@discardableResult
	public func startWithCompleted(_ completed: @escaping () -> Void) -> Disposable {
		return start(Observer(completed: completed))
	}
	
	/// Creates a Signal from the producer, then adds exactly one observer to
	/// the Signal, which will invoke the given callback when a `failed` event
	/// is received.
	///
	/// - parameters:
	///   - failed: A closure that accepts an error object.
	///
	/// - returns: A `Disposable` which can be used to interrupt the work
	///            associated with the signal.
	@discardableResult
	public func startWithFailed(_ failed: @escaping (Error) -> Void) -> Disposable {
		return start(Observer(failed: failed))
	}
	
	/// Creates a Signal from the producer, then adds exactly one observer to
	/// the Signal, which will invoke the given callback when an `interrupted`
	/// event is received.
	///
	/// - parameters:
	///   - interrupted: A closure that is invoked when `interrupted` event is
	///                  received.
	///
	/// - returns: A `Disposable` which can be used to interrupt the work
	///            associated with the signal.
	@discardableResult
	public func startWithInterrupted(_ interrupted: @escaping () -> Void) -> Disposable {
		return start(Observer(interrupted: interrupted))
	}
	
	/// Creates a `Signal` from the producer.
	///
	/// This is equivalent to `SignalProducer.startWithSignal`, but it has 
	/// the downside that any values emitted synchronously upon starting will 
	/// be missed by the observer, because it won't be able to subscribe in time.
	/// That's why we don't want this method to be exposed as `public`, 
	/// but it's useful internally.
	internal func startAndRetrieveSignal() -> Signal<Value, Error> {
		var result: Signal<Value, Error>!
		self.startWithSignal { signal, _ in
			result = signal
		}
		
		return result
	}
}

extension SignalProducerProtocol where Error == NoError {
	/// Create a Signal from the producer, then add exactly one observer to
	/// the Signal, which will invoke the given callback when `value` events are
	/// received.
	///
	/// - parameters:
	///   - value: A closure that accepts a value carried by `value` event.
	///
	/// - returns: A `Disposable` which can be used to interrupt the work
	///            associated with the Signal, and prevent any future callbacks
	///            from being invoked.
	@discardableResult
	public func startWithValues(_ value: @escaping (Value) -> Void) -> Disposable {
		return start(Observer(value: value))
	}
}

extension SignalProducerProtocol {
	/// Lift an unary Signal operator to operate upon SignalProducers instead.
	///
	/// In other words, this will create a new `SignalProducer` which will apply
	/// the given `Signal` operator to _every_ created `Signal`, just as if the
	/// operator had been applied to each `Signal` yielded from `start()`.
	///
	/// - parameters:
	///   - transform: An unary operator to lift.
	///
	/// - returns: A signal producer that applies signal's operator to every
	///            created signal.
	public func lift<U, F>(_ transform: @escaping (Signal<Value, Error>) -> Signal<U, F>) -> SignalProducer<U, F> {
		return SignalProducer { observer, outerDisposable in
			self.startWithSignal { signal, innerDisposable in
				outerDisposable += innerDisposable

				transform(signal).observe(observer)
			}
		}
	}
	

	/// Lift a binary Signal operator to operate upon SignalProducers instead.
	///
	/// In other words, this will create a new `SignalProducer` which will apply
	/// the given `Signal` operator to _every_ `Signal` created from the two
	/// producers, just as if the operator had been applied to each `Signal`
	/// yielded from `start()`.
	///
	/// - note: starting the returned producer will start the receiver of the
	///         operator, which may not be adviseable for some operators.
	///
	/// - parameters:
	///   - transform: A binary operator to lift.
	///
	/// - returns: A binary operator that operates on two signal producers.
	public func lift<U, F, V, G>(_ transform: @escaping (Signal<Value, Error>) -> (Signal<U, F>) -> Signal<V, G>) -> (SignalProducer<U, F>) -> SignalProducer<V, G> {
		return liftRight(transform)
	}

	/// Right-associative lifting of a binary signal operator over producers.
	/// That is, the argument producer will be started before the receiver. When
	/// both producers are synchronous this order can be important depending on
	/// the operator to generate correct results.
	private func liftRight<U, F, V, G>(_ transform: @escaping (Signal<Value, Error>) -> (Signal<U, F>) -> Signal<V, G>) -> (SignalProducer<U, F>) -> SignalProducer<V, G> {
		return { otherProducer in
			return SignalProducer { observer, outerDisposable in
				self.startWithSignal { signal, disposable in
					outerDisposable.add(disposable)

					otherProducer.startWithSignal { otherSignal, otherDisposable in
						outerDisposable += otherDisposable

						transform(signal)(otherSignal).observe(observer)
					}
				}
			}
		}
	}

	/// Left-associative lifting of a binary signal operator over producers.
	/// That is, the receiver will be started before the argument producer. When
	/// both producers are synchronous this order can be important depending on
	/// the operator to generate correct results.
	fileprivate func liftLeft<U, F, V, G>(_ transform: @escaping (Signal<Value, Error>) -> (Signal<U, F>) -> Signal<V, G>) -> (SignalProducer<U, F>) -> SignalProducer<V, G> {
		return { otherProducer in
			return SignalProducer { observer, outerDisposable in
				otherProducer.startWithSignal { otherSignal, otherDisposable in
					outerDisposable += otherDisposable
					
					self.startWithSignal { signal, disposable in
						outerDisposable.add(disposable)

						transform(signal)(otherSignal).observe(observer)
					}
				}
			}
		}
	}

	/// Lift a binary Signal operator to operate upon a Signal and a
	/// SignalProducer instead.
	///
	/// In other words, this will create a new `SignalProducer` which will apply
	/// the given `Signal` operator to _every_ `Signal` created from the two
	/// producers, just as if the operator had been applied to each `Signal`
	/// yielded from `start()`.
	///
	/// - parameters:
	///   - transform: A binary operator to lift.
	///
	/// - returns: A binary operator that works on `Signal` and returns
	///            `SignalProducer`.
	public func lift<U, F, V, G>(_ transform: @escaping (Signal<Value, Error>) -> (Signal<U, F>) -> Signal<V, G>) -> (Signal<U, F>) -> SignalProducer<V, G> {
		return { otherSignal in
			return self.liftRight(transform)(SignalProducer(otherSignal))
		}
	}

	/// Map each value in the producer to a new value.
	///
	/// - parameters:
	///   - transform: A closure that accepts a value and returns a different
	///                value.
	///
	/// - returns: A signal producer that, when started, will send a mapped
	///            value of `self.`
	public func map<U>(_ transform: @escaping (Value) -> U) -> SignalProducer<U, Error> {
		return lift { $0.map(transform) }
	}

	/// Map errors in the producer to a new error.
	///
	/// - parameters:
	///   - transform: A closure that accepts an error object and returns a
	///                different error.
	///
	/// - returns: A producer that emits errors of new type.
	public func mapError<F>(_ transform: @escaping (Error) -> F) -> SignalProducer<Value, F> {
		return lift { $0.mapError(transform) }
	}

	/// Maps each value in the producer to a new value, lazily evaluating the
	/// supplied transformation on the specified scheduler.
	///
	/// - important: Unlike `map`, there is not a 1-1 mapping between incoming 
	///              values, and values sent on the returned producer. If 
	///              `scheduler` has not yet scheduled `transform` for 
	///              execution, then each new value will replace the last one as 
	///              the parameter to `transform` once it is finally executed.
	///
	/// - parameters:
	///   - transform: The closure used to obtain the returned value from this
	///                producer's underlying value.
	///
	/// - returns: A producer that, when started, sends values obtained using 
	///            `transform` as this producer sends values.
	public func lazyMap<U>(on scheduler: Scheduler, transform: @escaping (Value) -> U) -> SignalProducer<U, Error> {
		return lift { $0.lazyMap(on: scheduler, transform: transform) }
	}

	/// Preserve only the values of the producer that pass the given predicate.
	///
	/// - parameters:
	///   - predicate: A closure that accepts value and returns `Bool` denoting
	///                whether value has passed the test.
	///
	/// - returns: A producer that, when started, will send only the values
	///            passing the given predicate.
	public func filter(_ predicate: @escaping (Value) -> Bool) -> SignalProducer<Value, Error> {
		return lift { $0.filter(predicate) }
	}

	/// Applies `transform` to values from the producer and forwards values with non `nil` results unwrapped.
	/// - parameters:
	///   - transform: A closure that accepts a value from the `value` event and
	///                returns a new optional value.
	///
	/// - returns: A producer that will send new values, that are non `nil` after the transformation.
	public func filterMap<U>(_ transform: @escaping (Value) -> U?) -> SignalProducer<U, Error> {
		return lift { $0.filterMap(transform) }
	}
	
	/// Yield the first `count` values from the input producer.
	///
	/// - precondition: `count` must be non-negative number.
	///
	/// - parameters:
	///   - count: A number of values to take from the signal.
	///
	/// - returns: A producer that, when started, will yield the first `count`
	///            values from `self`.
	public func take(first count: Int) -> SignalProducer<Value, Error> {
		return lift { $0.take(first: count) }
	}

	/// Yield an array of values when `self` completes.
	///
	/// - note: When `self` completes without collecting any value, it will send
	///         an empty array of values.
	///
	/// - returns: A producer that, when started, will yield an array of values
	///            when `self` completes.
	public func collect() -> SignalProducer<[Value], Error> {
		return lift { $0.collect() }
	}

	/// Yield an array of values until it reaches a certain count.
	///
	/// - precondition: `count` should be greater than zero.
	///
	/// - note: When the count is reached the array is sent and the signal
	///         starts over yielding a new array of values.
	///
	/// - note: When `self` completes any remaining values will be sent, the
	///         last array may not have `count` values. Alternatively, if were
	///         not collected any values will sent an empty array of values.
	///
	/// - returns: A producer that, when started, collects at most `count`
	///            values from `self`, forwards them as a single array and
	///            completes.
	public func collect(count: Int) -> SignalProducer<[Value], Error> {
		precondition(count > 0)
		return lift { $0.collect(count: count) }
	}

	/// Yield an array of values based on a predicate which matches the values
	/// collected.
	///
	/// - note: When `self` completes any remaining values will be sent, the
	///         last array may not match `predicate`. Alternatively, if were not
	///         collected any values will sent an empty array of values.
	///
	/// ````
	/// let (producer, observer) = SignalProducer<Int, NoError>.buffer(1)
	///
	/// producer
	///     .collect { values in values.reduce(0, combine: +) == 8 }
	///     .startWithValues { print($0) }
	///
	/// observer.send(value: 1)
	/// observer.send(value: 3)
	/// observer.send(value: 4)
	/// observer.send(value: 7)
	/// observer.send(value: 1)
	/// observer.send(value: 5)
	/// observer.send(value: 6)
	/// observer.sendCompleted()
	///
	/// // Output:
	/// // [1, 3, 4]
	/// // [7, 1]
	/// // [5, 6]
	/// ````
	///
	/// - parameters:
	///   - predicate: Predicate to match when values should be sent (returning
	///                `true`) or alternatively when they should be collected
	///                (where it should return `false`). The most recent value
	///                (`value`) is included in `values` and will be the end of
	///                the current array of values if the predicate returns
	///                `true`.
	///
	/// - returns: A producer that, when started, collects values passing the
	///            predicate and, when `self` completes, forwards them as a
	///            single array and complets.
	public func collect(_ predicate: @escaping (_ values: [Value]) -> Bool) -> SignalProducer<[Value], Error> {
		return lift { $0.collect(predicate) }
	}

	/// Yield an array of values based on a predicate which matches the values
	/// collected and the next value.
	///
	/// - note: When `self` completes any remaining values will be sent, the
	///         last array may not match `predicate`. Alternatively, if no
	///         values were collected an empty array will be sent.
	///
	/// ````
	/// let (producer, observer) = SignalProducer<Int, NoError>.buffer(1)
	///
	/// producer
	///     .collect { values, value in value == 7 }
	///     .startWithValues { print($0) }
	///
	/// observer.send(value: 1)
	/// observer.send(value: 1)
	/// observer.send(value: 7)
	/// observer.send(value: 7)
	/// observer.send(value: 5)
	/// observer.send(value: 6)
	/// observer.sendCompleted()
	///
	/// // Output:
	/// // [1, 1]
	/// // [7]
	/// // [7, 5, 6]
	/// ````
	///
	/// - parameters:
	///   - predicate: Predicate to match when values should be sent (returning
	///                `true`) or alternatively when they should be collected
	///                (where it should return `false`). The most recent value
	///                (`vaule`) is not included in `values` and will be the
	///                start of the next array of values if the predicate
	///                returns `true`.
	///
	/// - returns: A signal that will yield an array of values based on a
	///            predicate which matches the values collected and the next
	///            value.
	public func collect(_ predicate: @escaping (_ values: [Value], _ value: Value) -> Bool) -> SignalProducer<[Value], Error> {
		return lift { $0.collect(predicate) }
	}

	/// Forward all events onto the given scheduler, instead of whichever
	/// scheduler they originally arrived upon.
	///
	/// - parameters:
	///   - scheduler: A scheduler to deliver events on.
	///
	/// - returns: A producer that, when started, will yield `self` values on
	///            provided scheduler.
	public func observe(on scheduler: Scheduler) -> SignalProducer<Value, Error> {
		return lift { $0.observe(on: scheduler) }
	}

	/// Combine the latest value of the receiver with the latest value from the
	/// given producer.
	///
	/// - note: The returned producer will not send a value until both inputs
	///         have sent at least one value each. 
	///
	/// - note: If either producer is interrupted, the returned producer will
	///         also be interrupted.
	///
	/// - note: The returned producer will not complete until both inputs
	///         complete.
	///
	/// - parameters:
	///   - other: A producer to combine `self`'s value with.
	///
	/// - returns: A producer that, when started, will yield a tuple containing
	///            values of `self` and given producer.
	public func combineLatest<U>(with other: SignalProducer<U, Error>) -> SignalProducer<(Value, U), Error> {
		return liftLeft(Signal.combineLatest)(other)
	}

	/// Combine the latest value of the receiver with the latest value from
	/// the given signal.
	///
	/// - note: The returned producer will not send a value until both inputs
	///         have sent at least one value each. 
	///
	/// - note: If either input is interrupted, the returned producer will also
	///         be interrupted.
	///
	/// - note: The returned producer will not complete until both inputs
	///         complete.
	///
	/// - parameters:
	///   - other: A signal to combine `self`'s value with.
	///
	/// - returns: A producer that, when started, will yield a tuple containing
	///            values of `self` and given signal.
	public func combineLatest<U>(with other: Signal<U, Error>) -> SignalProducer<(Value, U), Error> {
		return lift(Signal.combineLatest(with:))(other)
	}

	/// Delay `value` and `completed` events by the given interval, forwarding
	/// them on the given scheduler.
	///
	/// - note: `failed` and `interrupted` events are always scheduled
	///         immediately.
	///
	/// - parameters:
	///   - interval: Interval to delay `value` and `completed` events by.
	///   - scheduler: A scheduler to deliver delayed events on.
	///
	/// - returns: A producer that, when started, will delay `value` and
	///            `completed` events and will yield them on given scheduler.
	public func delay(_ interval: TimeInterval, on scheduler: DateScheduler) -> SignalProducer<Value, Error> {
		return lift { $0.delay(interval, on: scheduler) }
	}

	/// Skip the first `count` values, then forward everything afterward.
	///
	/// - parameters:
	///   - count: A number of values to skip.
	///
	/// - returns:  A producer that, when started, will skip the first `count`
	///             values, then forward everything afterward.
	public func skip(first count: Int) -> SignalProducer<Value, Error> {
		return lift { $0.skip(first: count) }
	}

	/// Treats all Events from the input producer as plain values, allowing them
	/// to be manipulated just like any other value.
	///
	/// In other words, this brings Events “into the monad.”
	///
	/// - note: When a Completed or Failed event is received, the resulting
	///         producer will send the Event itself and then complete. When an
	///         `interrupted` event is received, the resulting producer will
	///         send the `Event` itself and then interrupt.
	///
	/// - returns: A producer that sends events as its values.
	public func materialize() -> SignalProducer<Event<Value, Error>, NoError> {
		return lift { $0.materialize() }
	}

	/// Forward the latest value from `self` with the value from `sampler` as a
	/// tuple, only when `sampler` sends a `value` event.
	///
	/// - note: If `sampler` fires before a value has been observed on `self`,
	///         nothing happens.
	///
	/// - parameters:
	///   - sampler: A producer that will trigger the delivery of `value` event
	///              from `self`.
	///
	/// - returns: A producer that will send values from `self` and `sampler`,
	///            sampled (possibly multiple times) by `sampler`, then complete
	///            once both input producers have completed, or interrupt if
	///            either input producer is interrupted.
	public func sample<T>(with sampler: SignalProducer<T, NoError>) -> SignalProducer<(Value, T), Error> {
		return liftLeft(Signal.sample(with:))(sampler)
	}
	
	/// Forward the latest value from `self` with the value from `sampler` as a
	/// tuple, only when `sampler` sends a `value` event.
	///
	/// - note: If `sampler` fires before a value has been observed on `self`,
	///         nothing happens.
	///
	/// - parameters:
	///   - sampler: A signal that will trigger the delivery of `value` event
	///              from `self`.
	///
	/// - returns: A producer that, when started, will send values from `self`
	///            and `sampler`, sampled (possibly multiple times) by
	///            `sampler`, then complete once both input producers have
	///            completed, or interrupt if either input producer is
	///            interrupted.
	public func sample<T>(with sampler: Signal<T, NoError>) -> SignalProducer<(Value, T), Error> {
		return lift(Signal.sample(with:))(sampler)
	}

	/// Forward the latest value from `self` whenever `sampler` sends a `value`
	/// event.
	///
	/// - note: If `sampler` fires before a value has been observed on `self`,
	///         nothing happens.
	///
	/// - parameters:
	///   - sampler: A producer that will trigger the delivery of `value` event
	///              from `self`.
	///
	/// - returns: A producer that, when started, will send values from `self`,
	///            sampled (possibly multiple times) by `sampler`, then complete
	///            once both input producers have completed, or interrupt if
	///            either input producer is interrupted.
	public func sample(on sampler: SignalProducer<(), NoError>) -> SignalProducer<Value, Error> {
		return liftLeft(Signal.sample(on:))(sampler)
	}

	/// Forward the latest value from `self` whenever `sampler` sends a `value`
	/// event.
	///
	/// - note: If `sampler` fires before a value has been observed on `self`,
	///         nothing happens.
	///
	/// - parameters:
	///   - trigger: A signal whose `value` or `completed` events will start the
	///              deliver of events on `self`.
	///
	/// - returns: A producer that will send values from `self`, sampled
	///            (possibly multiple times) by `sampler`, then complete once 
	///            both inputs have completed, or interrupt if either input is
	///            interrupted.
	public func sample(on sampler: Signal<(), NoError>) -> SignalProducer<Value, Error> {
		return lift(Signal.sample(on:))(sampler)
	}

	/// Forward the latest value from `samplee` with the value from `self` as a
	/// tuple, only when `self` sends a `value` event.
	/// This is like a flipped version of `sample(with:)`, but `samplee`'s
	/// terminal events are completely ignored.
	///
	/// - note: If `self` fires before a value has been observed on `samplee`,
	///         nothing happens.
	///
	/// - parameters:
	///   - samplee: A producer whose latest value is sampled by `self`.
	///
	/// - returns: A signal that will send values from `self` and `samplee`,
	///            sampled (possibly multiple times) by `self`, then terminate
	///            once `self` has terminated. **`samplee`'s terminated events
	///            are ignored**.
	public func withLatest<U>(from samplee: SignalProducer<U, NoError>) -> SignalProducer<(Value, U), Error> {
		return liftRight(Signal.withLatest)(samplee)
	}

	/// Forward the latest value from `samplee` with the value from `self` as a
	/// tuple, only when `self` sends a `value` event.
	/// This is like a flipped version of `sample(with:)`, but `samplee`'s
	/// terminal events are completely ignored.
	///
	/// - note: If `self` fires before a value has been observed on `samplee`,
	///         nothing happens.
	///
	/// - parameters:
	///   - samplee: A signal whose latest value is sampled by `self`.
	///
	/// - returns: A signal that will send values from `self` and `samplee`,
	///            sampled (possibly multiple times) by `self`, then terminate
	///            once `self` has terminated. **`samplee`'s terminated events
	///            are ignored**.
	public func withLatest<U>(from samplee: Signal<U, NoError>) -> SignalProducer<(Value, U), Error> {
		return lift(Signal.withLatest)(samplee)
	}

	/// Forwards events from `self` until `lifetime` ends, at which point the
	/// returned producer will complete.
	///
	/// - parameters:
	///   - lifetime: A lifetime whose `ended` signal will cause the returned
	///               producer to complete.
	///
	/// - returns: A producer that will deliver events until `lifetime` ends.
	public func take(during lifetime: Lifetime) -> SignalProducer<Value, Error> {
		return lift { $0.take(during: lifetime) }
	}

	/// Forward events from `self` until `trigger` sends a `value` or `completed`
	/// event, at which point the returned producer will complete.
	///
	/// - parameters:
	///   - trigger: A producer whose `value` or `completed` events will stop the
	///              delivery of `value` events from `self`.
	///
	/// - returns: A producer that will deliver events until `trigger` sends
	///            `value` or `completed` events.
	public func take(until trigger: SignalProducer<(), NoError>) -> SignalProducer<Value, Error> {
		return liftRight(Signal.take(until:))(trigger)
	}

	/// Forward events from `self` until `trigger` sends a `value` or
	/// `completed` event, at which point the returned producer will complete.
	///
	/// - parameters:
	///   - trigger: A signal whose `value` or `completed` events will stop the
	///              delivery of `value` events from `self`.
	///
	/// - returns: A producer that will deliver events until `trigger` sends
	///            `value` or `completed` events.
	public func take(until trigger: Signal<(), NoError>) -> SignalProducer<Value, Error> {
		return lift(Signal.take(until:))(trigger)
	}

	/// Do not forward any values from `self` until `trigger` sends a `value`
	/// or `completed`, at which point the returned producer behaves exactly
	/// like `producer`.
	///
	/// - parameters:
	///   - trigger: A producer whose `value` or `completed` events will start
	///              the deliver of events on `self`.
	///
	/// - returns: A producer that will deliver events once the `trigger` sends
	///            `value` or `completed` events.
	public func skip(until trigger: SignalProducer<(), NoError>) -> SignalProducer<Value, Error> {
		return liftRight(Signal.skip(until:))(trigger)
	}
	
	/// Do not forward any values from `self` until `trigger` sends a `value`
	/// or `completed`, at which point the returned signal behaves exactly like
	/// `signal`.
	///
	/// - parameters:
	///   - trigger: A signal whose `value` or `completed` events will start the
	///              deliver of events on `self`.
	///
	/// - returns: A producer that will deliver events once the `trigger` sends
	///            `value` or `completed` events.
	public func skip(until trigger: Signal<(), NoError>) -> SignalProducer<Value, Error> {
		return lift(Signal.skip(until:))(trigger)
	}
	
	/// Forward events from `self` with history: values of the returned producer
	/// are a tuple whose first member is the previous value and whose second
	/// member is the current value. `initial` is supplied as the first member
	/// when `self` sends its first value.
	///
	/// - parameters:
	///   - initial: A value that will be combined with the first value sent by
	///              `self`.
	///
	/// - returns: A producer that sends tuples that contain previous and
	///            current sent values of `self`.
	public func combinePrevious(_ initial: Value) -> SignalProducer<(Value, Value), Error> {
		return lift { $0.combinePrevious(initial) }
	}

	/// Send only the final value and then immediately completes.
	///
	/// - parameters:
	///   - initial: Initial value for the accumulator.
	///   - combine: A closure that accepts accumulator and sent value of
	///              `self`.
	///
	/// - returns: A producer that sends accumulated value after `self`
	///             completes.
	public func reduce<U>(_ initial: U, _ combine: @escaping (U, Value) -> U) -> SignalProducer<U, Error> {
		return lift { $0.reduce(initial, combine) }
	}

	/// Aggregate `self`'s values into a single combined value. When `self`
	/// emits its first value, `combine` is invoked with `initial` as the first
	/// argument and that emitted value as the second argument. The result is
	/// emitted from the producer returned from `scan`. That result is then
	/// passed to `combine` as the first argument when the next value is
	/// emitted, and so on.
	///
	/// - parameters:
	///   - initial: Initial value for the accumulator.
	///   - combine: A closure that accepts accumulator and sent value of
	///              `self`.
	///
	/// - returns: A producer that sends accumulated value each time `self`
	///            emits own value.
	public func scan<U>(_ initial: U, _ combine: @escaping (U, Value) -> U) -> SignalProducer<U, Error> {
		return lift { $0.scan(initial, combine) }
	}

	/// Forward only those values from `self` which do not pass `isRepeat` with
	/// respect to the previous value.
	///
	/// - note: The first value is always forwarded.
	///
	/// - returns: A producer that does not send two equal values sequentially.
	public func skipRepeats(_ isRepeat: @escaping (Value, Value) -> Bool) -> SignalProducer<Value, Error> {
		return lift { $0.skipRepeats(isRepeat) }
	}

	/// Do not forward any values from `self` until `predicate` returns false,
	/// at which point the returned producer behaves exactly like `self`.
	///
	/// - parameters:
	///   - predicate: A closure that accepts a value and returns whether `self`
	///                should still not forward that value to a `producer`.
	///
	/// - returns: A producer that sends only forwarded values from `self`.
	public func skip(while predicate: @escaping (Value) -> Bool) -> SignalProducer<Value, Error> {
		return lift { $0.skip(while: predicate) }
	}

	/// Forward events from `self` until `replacement` begins sending events.
	///
	/// - parameters:
	///   - replacement: A producer to wait to wait for values from and start
	///                  sending them as a replacement to `self`'s values.
	///
	/// - returns: A producer which passes through `value`, `failed`, and
	///            `interrupted` events from `self` until `replacement` sends an 
	///            event, at which point the returned producer will send that
	///            event and switch to passing through events from `replacement` 
	///            instead, regardless of whether `self` has sent events
	///            already.
	public func take(untilReplacement signal: SignalProducer<Value, Error>) -> SignalProducer<Value, Error> {
		return liftRight(Signal.take(untilReplacement:))(signal)
	}

	/// Forwards events from `self` until `replacement` begins sending events.
	///
	/// - parameters:
	///   - replacement: A signal to wait to wait for values from and start
	///                  sending them as a replacement to `self`'s values.
	///
	/// - returns: A producer which passes through `value`, `failed`, and
	///            `interrupted` events from `self` until `replacement` sends an
	///            event, at which point the returned producer will send that
	///            event and switch to passing through events from `replacement`
	///            instead, regardless of whether `self` has sent events
	///            already.
	public func take(untilReplacement signal: Signal<Value, Error>) -> SignalProducer<Value, Error> {
		return lift(Signal.take(untilReplacement:))(signal)
	}

	/// Wait until `self` completes and then forward the final `count` values
	/// on the returned producer.
	///
	/// - parameters:
	///   - count: Number of last events to send after `self` completes.
	///
	/// - returns: A producer that receives up to `count` values from `self`
	///            after `self` completes.
	public func take(last count: Int) -> SignalProducer<Value, Error> {
		return lift { $0.take(last: count) }
	}

	/// Forward any values from `self` until `predicate` returns false, at which
	/// point the returned producer will complete.
	///
	/// - parameters:
	///   - predicate: A closure that accepts value and returns `Bool` value
	///                whether `self` should forward it to `signal` and continue
	///                sending other events.
	///
	/// - returns: A producer that sends events until the values sent by `self`
	///            pass the given `predicate`.
	public func take(while predicate: @escaping (Value) -> Bool) -> SignalProducer<Value, Error> {
		return lift { $0.take(while: predicate) }
	}

	/// Zip elements of two producers into pairs. The elements of any Nth pair
	/// are the Nth elements of the two input producers.
	///
	/// - parameters:
	///   - other: A producer to zip values with.
	///
	/// - returns: A producer that sends tuples of `self` and `otherProducer`.
	public func zip<U>(with other: SignalProducer<U, Error>) -> SignalProducer<(Value, U), Error> {
		return liftLeft(Signal.zip(with:))(other)
	}

	/// Zip elements of this producer and a signal into pairs. The elements of
	/// any Nth pair are the Nth elements of the two.
	///
	/// - parameters:
	///   - other: A signal to zip values with.
	///
	/// - returns: A producer that sends tuples of `self` and `otherSignal`.
	public func zip<U>(with other: Signal<U, Error>) -> SignalProducer<(Value, U), Error> {
		return lift(Signal.zip(with:))(other)
	}

	/// Apply `operation` to values from `self` with `success`ful results
	/// forwarded on the returned producer and `failure`s sent as `failed`
	/// events.
	///
	/// - parameters:
	///   - operation: A closure that accepts a value and returns a `Result`.
	///
	/// - returns: A producer that receives `success`ful `Result` as `value`
	///            event and `failure` as `failed` event.
	public func attempt(operation: @escaping (Value) -> Result<(), Error>) -> SignalProducer<Value, Error> {
		return lift { $0.attempt(operation) }
	}

	/// Apply `operation` to values from `self` with `success`ful results
	/// mapped on the returned producer and `failure`s sent as `failed` events.
	///
	/// - parameters:
	///   - operation: A closure that accepts a value and returns a result of
	///                a mapped value as `success`.
	///
	/// - returns: A producer that sends mapped values from `self` if returned
	///            `Result` is `success`ful, `failed` events otherwise.
	public func attemptMap<U>(_ operation: @escaping (Value) -> Result<U, Error>) -> SignalProducer<U, Error> {
		return lift { $0.attemptMap(operation) }
	}

	/// Forward the latest value on `scheduler` after at least `interval`
	/// seconds have passed since *the returned signal* last sent a value.
	///
	/// If `self` always sends values more frequently than `interval` seconds,
	/// then the returned signal will send a value every `interval` seconds.
	///
	/// To measure from when `self` last sent a value, see `debounce`.
	///
	/// - seealso: `debounce`
	///
	/// - note: If multiple values are received before the interval has elapsed,
	///         the latest value is the one that will be passed on.
	///
	/// - note: If `self` terminates while a value is being throttled, that
	///         value will be discarded and the returned producer will terminate
	///         immediately.
	///
	/// - note: If the device time changed backwards before previous date while
	///         a value is being throttled, and if there is a new value sent,
	///         the new value will be passed anyway.
	///
	/// - parameters:
	///   - interval: Number of seconds to wait between sent values.
	///   - scheduler: A scheduler to deliver events on.
	///
	/// - returns: A producer that sends values at least `interval` seconds
	///            appart on a given scheduler.
	public func throttle(_ interval: TimeInterval, on scheduler: DateScheduler) -> SignalProducer<Value, Error> {
		return lift { $0.throttle(interval, on: scheduler) }
	}

	/// Conditionally throttles values sent on the receiver whenever
	/// `shouldThrottle` is true, forwarding values on the given scheduler.
	///
	/// - note: While `shouldThrottle` remains false, values are forwarded on the
	///         given scheduler. If multiple values are received while
	///         `shouldThrottle` is true, the latest value is the one that will
	///         be passed on.
	///
	/// - note: If the input signal terminates while a value is being throttled,
	///         that value will be discarded and the returned signal will
	///         terminate immediately.
	///
	/// - note: If `shouldThrottle` completes before the receiver, and its last
	///         value is `true`, the returned signal will remain in the throttled
	///         state, emitting no further values until it terminates.
	///
	/// - parameters:
	///   - shouldThrottle: A boolean property that controls whether values
	///                     should be throttled.
	///   - scheduler: A scheduler to deliver events on.
	///
	/// - returns: A producer that sends values only while `shouldThrottle` is false.
	public func throttle<P: PropertyProtocol>(while shouldThrottle: P, on scheduler: Scheduler) -> SignalProducer<Value, Error>
		where P.Value == Bool
	{
		// Using `Property.init(_:)` avoids capturing a strong reference
		// to `shouldThrottle`, so that we don't extend its lifetime.
		let shouldThrottle = Property(shouldThrottle)

		return lift { $0.throttle(while: shouldThrottle, on: scheduler) }
	}

	/// Forward the latest value on `scheduler` after at least `interval`
	/// seconds have passed since `self` last sent a value.
	///
	/// If `self` always sends values more frequently than `interval` seconds,
	/// then the returned signal will never send any values.
	///
	/// To measure from when the *returned signal* last sent a value, see
	/// `throttle`.
	///
	/// - seealso: `throttle`
	///
	/// - note: If multiple values are received before the interval has elapsed,
	///         the latest value is the one that will be passed on.
	///
	/// - note: If `self` terminates while a value is being debounced,
	///         that value will be discarded and the returned producer will
	///         terminate immediately.
	///
	/// - parameters:
	///   - interval: A number of seconds to wait before sending a value.
	///   - scheduler: A scheduler to send values on.
	///
	/// - returns: A producer that sends values that are sent from `self` at
	///            least `interval` seconds apart.
	public func debounce(_ interval: TimeInterval, on scheduler: DateScheduler) -> SignalProducer<Value, Error> {
		return lift { $0.debounce(interval, on: scheduler) }
	}

	/// Forward events from `self` until `interval`. Then if producer isn't
	/// completed yet, fails with `error` on `scheduler`.
	///
	/// - note: If the interval is 0, the timeout will be scheduled immediately.
	///         The producer must complete synchronously (or on a faster 
	///         scheduler) to avoid the timeout.
	///
	/// - parameters:
	///   - interval: Number of seconds to wait for `self` to complete.
	///   - error: Error to send with `failed` event if `self` is not completed
	///            when `interval` passes.
	///   - scheduler: A scheduler to deliver error on.
	///
	/// - returns: A producer that sends events for at most `interval` seconds,
	///            then, if not `completed` - sends `error` with `failed` event
	///            on `scheduler`.
	public func timeout(after interval: TimeInterval, raising error: Error, on scheduler: DateScheduler) -> SignalProducer<Value, Error> {
		return lift { $0.timeout(after: interval, raising: error, on: scheduler) }
	}
}

extension SignalProducerProtocol where Value: OptionalProtocol {
	/// Unwraps non-`nil` values and forwards them on the returned signal, `nil`
	/// values are dropped.
	///
	/// - returns: A producer that sends only non-nil values.
	public func skipNil() -> SignalProducer<Value.Wrapped, Error> {
		return lift { $0.skipNil() }
	}
}

extension SignalProducerProtocol where Value: EventProtocol, Error == NoError {
	/// The inverse of materialize(), this will translate a producer of `Event`
	/// _values_ into a producer of those events themselves.
	///
	/// - returns: A producer that sends values carried by `self` events.
	public func dematerialize() -> SignalProducer<Value.Value, Value.Error> {
		return lift { $0.dematerialize() }
	}
}

extension SignalProducerProtocol where Error == NoError {
	/// Promote a producer that does not generate failures into one that can.
	///
	/// - note: This does not actually cause failers to be generated for the
	///         given producer, but makes it easier to combine with other
	///         producers that may fail; for example, with operators like
	///         `combineLatestWith`, `zipWith`, `flatten`, etc.
	///
	/// - parameters:
	///   - _ An `ErrorType`.
	///
	/// - returns: A producer that has an instantiatable `ErrorType`.
	public func promoteErrors<F: Swift.Error>(_: F.Type) -> SignalProducer<Value, F> {
		return lift { $0.promoteErrors(F.self) }
	}

	/// Forward events from `self` until `interval`. Then if producer isn't
	/// completed yet, fails with `error` on `scheduler`.
	///
	/// - note: If the interval is 0, the timeout will be scheduled immediately.
	///         The producer must complete synchronously (or on a faster
	///         scheduler) to avoid the timeout.
	///
	/// - parameters:
	///   - interval: Number of seconds to wait for `self` to complete.
	///   - error: Error to send with `failed` event if `self` is not completed
	///            when `interval` passes.
	///   - scheudler: A scheduler to deliver error on.
	///
	/// - returns: A producer that sends events for at most `interval` seconds,
	///            then, if not `completed` - sends `error` with `failed` event
	///            on `scheduler`.
	public func timeout<NewError: Swift.Error>(
		after interval: TimeInterval,
		raising error: NewError,
		on scheduler: DateScheduler
	) -> SignalProducer<Value, NewError> {
		return lift { $0.timeout(after: interval, raising: error, on: scheduler) }
	}

	/// Wait for completion of `self`, *then* forward all events from
	/// `replacement`.
	///
	/// - note: All values sent from `self` are ignored.
	///
	/// - parameters:
	///   - replacement: A producer to start when `self` completes.
	///
	/// - returns: A producer that sends events from `self` and then from
	///            `replacement` when `self` completes.
	public func then<U, NewError: Swift.Error>(_ replacement: SignalProducer<U, NewError>) -> SignalProducer<U, NewError> {
		return self
			.promoteErrors(NewError.self)
			.then(replacement)
	}

	/// Apply a failable `operation` to values from `self` with successful
	/// results forwarded on the returned producer and thrown errors sent as
	/// failed events.
	///
	/// - parameters:
	///   - operation: A failable closure that accepts a value.
	///
	/// - returns: A producer that forwards successes as `value` events and thrown
	///            errors as `failed` events.
	public func attempt(_ operation: @escaping (Value) throws -> Void) -> SignalProducer<Value, AnyError> {
		return lift { $0.attempt(operation) }
	}

	/// Apply a failable `operation` to values from `self` with successful
	/// results mapped on the returned producer and thrown errors sent as
	/// failed events.
	///
	/// - parameters:
	///   - operation: A failable closure that accepts a value and attempts to
	///                transform it.
	///
	/// - returns: A producer that sends successfully mapped values from `self`,
	///            or thrown errors as `failed` events.
	public func attemptMap<U>(_ operation: @escaping (Value) throws -> U) -> SignalProducer<U, AnyError> {
		return lift { $0.attemptMap(operation) }
	}
}

extension SignalProducer {
	/// Create a `SignalProducer` that will attempt the given operation once for
	/// each invocation of `start()`.
	///
	/// Upon success, the started signal will send the resulting value then
	/// complete. Upon failure, the started signal will fail with the error that
	/// occurred.
	///
	/// - parameters:
	///   - operation: A closure that returns instance of `Result`.
	///
	/// - returns: A `SignalProducer` that will forward `success`ful `result` as
	///            `value` event and then complete or `failed` event if `result`
	///            is a `failure`.
	public static func attempt(_ operation: @escaping () -> Result<Value, Error>) -> SignalProducer {
		return self.init { observer, disposable in
			operation().analysis(ifSuccess: { value in
				observer.send(value: value)
				observer.sendCompleted()
				}, ifFailure: { error in
					observer.send(error: error)
			})
		}
	}
}

extension SignalProducerProtocol where Error == AnyError {
	/// Create a `SignalProducer` that will attempt the given failable operation once for
	/// each invocation of `start()`.
	///
	/// Upon success, the started producer will send the resulting value then
	/// complete. Upon failure, the started signal will fail with the error that
	/// occurred.
	///
	/// - parameters:
	///   - operation: A failable closure.
	///
	/// - returns: A `SignalProducer` that will forward a success as a `value`
	///            event and then complete or `failed` event if the closure throws.
	public static func attempt(_ operation: @escaping () throws -> Value) -> SignalProducer<Value, Error> {
		return .attempt {
			ReactiveSwift.materialize {
				try operation()
			}
		}
	}

	/// Apply a failable `operation` to values from `self` with successful
	/// results forwarded on the returned producer and thrown errors sent as
	/// failed events.
	///
	/// - parameters:
	///   - operation: A failable closure that accepts a value.
	///
	/// - returns: A producer that forwards successes as `value` events and thrown
	///            errors as `failed` events.
	public func attempt(_ operation: @escaping (Value) throws -> Void) -> SignalProducer<Value, AnyError> {
		return lift { $0.attempt(operation) }
	}

	/// Apply a failable `operation` to values from `self` with successful
	/// results mapped on the returned producer and thrown errors sent as
	/// failed events.
	///
	/// - parameters:
	///   - operation: A failable closure that accepts a value and attempts to
	///                transform it.
	///
	/// - returns: A producer that sends successfully mapped values from `self`,
	///            or thrown errors as `failed` events.
	public func attemptMap<U>(_ operation: @escaping (Value) throws -> U) -> SignalProducer<U, AnyError> {
		return lift { $0.attemptMap(operation) }
	}
}

extension SignalProducerProtocol where Value: Equatable {
	/// Forward only those values from `self` which are not duplicates of the
	/// immedately preceding value.
	///
	/// - note: The first value is always forwarded.
	///
	/// - returns: A producer that does not send two equal values sequentially.
	public func skipRepeats() -> SignalProducer<Value, Error> {
		return lift { $0.skipRepeats() }
	}
}

extension SignalProducerProtocol {
	/// Forward only those values from `self` that have unique identities across
	/// the set of all values that have been seen.
	///
	/// - note: This causes the identities to be retained to check for 
	///         uniqueness.
	///
	/// - parameters:
	///   - transform: A closure that accepts a value and returns identity
	///                value.
	///
	/// - returns: A producer that sends unique values during its lifetime.
	public func uniqueValues<Identity: Hashable>(_ transform: @escaping (Value) -> Identity) -> SignalProducer<Value, Error> {
		return lift { $0.uniqueValues(transform) }
	}
}

extension SignalProducerProtocol where Value: Hashable {
	/// Forward only those values from `self` that are unique across the set of
	/// all values that have been seen.
	///
	/// - note: This causes the values to be retained to check for uniqueness.
	///         Providing a function that returns a unique value for each sent
	///         value can help you reduce the memory footprint.
	///
	/// - returns: A producer that sends unique values during its lifetime.
	public func uniqueValues() -> SignalProducer<Value, Error> {
		return lift { $0.uniqueValues() }
	}
}

extension SignalProducerProtocol {
	/// Injects side effects to be performed upon the specified producer events.
	///
	/// - note: In a composed producer, `starting` is invoked in the reverse
	///         direction of the flow of events.
	///
	/// - parameters:
	///   - starting: A closure that is invoked before the producer is started.
	///   - started: A closure that is invoked after the producer is started.
	///   - event: A closure that accepts an event and is invoked on every
	///            received event.
	///   - failed: A closure that accepts error object and is invoked for
	///             `failed` event.
	///   - completed: A closure that is invoked for `completed` event.
	///   - interrupted: A closure that is invoked for `interrupted` event.
	///   - terminated: A closure that is invoked for any terminating event.
	///   - disposed: A closure added as disposable when signal completes.
	///   - value: A closure that accepts a value from `value` event.
	///
	/// - returns: A producer with attached side-effects for given event cases.
	public func on(
		starting: (() -> Void)? = nil,
		started: (() -> Void)? = nil,
		event: ((Event<Value, Error>) -> Void)? = nil,
		failed: ((Error) -> Void)? = nil,
		completed: (() -> Void)? = nil,
		interrupted: (() -> Void)? = nil,
		terminated: (() -> Void)? = nil,
		disposed: (() -> Void)? = nil,
		value: ((Value) -> Void)? = nil
	) -> SignalProducer<Value, Error> {
		return SignalProducer { observer, compositeDisposable in
			starting?()
			defer { started?() }

			self.startWithSignal { signal, disposable in
				compositeDisposable += disposable
				signal
					.on(
						event: event,
						failed: failed,
						completed: completed,
						interrupted: interrupted,
						terminated: terminated,
						disposed: disposed,
						value: value
					)
					.observe(observer)
			}
		}
	}

	/// Start the returned producer on the given `Scheduler`.
	///
	/// - note: This implies that any side effects embedded in the producer will
	///         be performed on the given scheduler as well.
	///
	/// - note: Events may still be sent upon other schedulers — this merely
	///         affects where the `start()` method is run.
	///
	/// - parameters:
	///   - scheduler: A scheduler to deliver events on.
	///
	/// - returns: A producer that will deliver events on given `scheduler` when
	///            started.
	public func start(on scheduler: Scheduler) -> SignalProducer<Value, Error> {
		return SignalProducer { observer, compositeDisposable in
			compositeDisposable += scheduler.schedule {
				self.startWithSignal { signal, signalDisposable in
					compositeDisposable += signalDisposable
					signal.observe(observer)
				}
			}
		}
	}
}

extension SignalProducerProtocol {
	/// Combines the values of all the given producers, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>) -> SignalProducer<(Value, B), Error> {
		return a.combineLatest(with: b)
	}

	/// Combines the values of all the given producers, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>) -> SignalProducer<(Value, B, C), Error> {
		return combineLatest(a, b)
			.combineLatest(with: c)
			.map(repack)
	}

	/// Combines the values of all the given producers, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>) -> SignalProducer<(Value, B, C, D), Error> {
		return combineLatest(a, b, c)
			.combineLatest(with: d)
			.map(repack)
	}

	/// Combines the values of all the given producers, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D, E>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>) -> SignalProducer<(Value, B, C, D, E), Error> {
		return combineLatest(a, b, c, d)
			.combineLatest(with: e)
			.map(repack)
	}

	/// Combines the values of all the given producers, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D, E, F>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>) -> SignalProducer<(Value, B, C, D, E, F), Error> {
		return combineLatest(a, b, c, d, e)
			.combineLatest(with: f)
			.map(repack)
	}

	/// Combines the values of all the given producers, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D, E, F, G>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>) -> SignalProducer<(Value, B, C, D, E, F, G), Error> {
		return combineLatest(a, b, c, d, e, f)
			.combineLatest(with: g)
			.map(repack)
	}

	/// Combines the values of all the given producers, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D, E, F, G, H>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>, _ h: SignalProducer<H, Error>) -> SignalProducer<(Value, B, C, D, E, F, G, H), Error> {
		return combineLatest(a, b, c, d, e, f, g)
			.combineLatest(with: h)
			.map(repack)
	}

	/// Combines the values of all the given producers, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D, E, F, G, H, I>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>, _ h: SignalProducer<H, Error>, _ i: SignalProducer<I, Error>) -> SignalProducer<(Value, B, C, D, E, F, G, H, I), Error> {
		return combineLatest(a, b, c, d, e, f, g, h)
			.combineLatest(with: i)
			.map(repack)
	}

	/// Combines the values of all the given producers, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D, E, F, G, H, I, J>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>, _ h: SignalProducer<H, Error>, _ i: SignalProducer<I, Error>, _ j: SignalProducer<J, Error>) -> SignalProducer<(Value, B, C, D, E, F, G, H, I, J), Error> {
		return combineLatest(a, b, c, d, e, f, g, h, i)
			.combineLatest(with: j)
			.map(repack)
	}

	/// Combines the values of all the given producers, in the manner described by
	/// `combineLatest(with:)`. Will return an empty `SignalProducer` if the sequence is empty.
	public static func combineLatest<S: Sequence>(_ producers: S) -> SignalProducer<[Value], Error>
		where S.Iterator.Element == SignalProducer<Value, Error>
	{
		var generator = producers.makeIterator()
		if let first = generator.next() {
			let initial = first.map { [$0] }
			return IteratorSequence(generator).reduce(initial) { producer, next in
				producer.combineLatest(with: next).map { $0.0 + [$0.1] }
			}
		}
		
		return .empty
	}

	/// Zips the values of all the given producers, in the manner described by
	/// `zipWith`.
	public static func zip<B>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>) -> SignalProducer<(Value, B), Error> {
		return a.zip(with: b)
	}

	/// Zips the values of all the given producers, in the manner described by
	/// `zipWith`.
	public static func zip<B, C>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>) -> SignalProducer<(Value, B, C), Error> {
		return zip(a, b)
			.zip(with: c)
			.map(repack)
	}

	/// Zips the values of all the given producers, in the manner described by
	/// `zipWith`.
	public static func zip<B, C, D>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>) -> SignalProducer<(Value, B, C, D), Error> {
		return zip(a, b, c)
			.zip(with: d)
			.map(repack)
	}

	/// Zips the values of all the given producers, in the manner described by
	/// `zipWith`.
	public static func zip<B, C, D, E>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>) -> SignalProducer<(Value, B, C, D, E), Error> {
		return zip(a, b, c, d)
			.zip(with: e)
			.map(repack)
	}

	/// Zips the values of all the given producers, in the manner described by
	/// `zipWith`.
	public static func zip<B, C, D, E, F>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>) -> SignalProducer<(Value, B, C, D, E, F), Error> {
		return zip(a, b, c, d, e)
			.zip(with: f)
			.map(repack)
	}

	/// Zips the values of all the given producers, in the manner described by
	/// `zipWith`.
	public static func zip<B, C, D, E, F, G>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>) -> SignalProducer<(Value, B, C, D, E, F, G), Error> {
		return zip(a, b, c, d, e, f)
			.zip(with: g)
			.map(repack)
	}

	/// Zips the values of all the given producers, in the manner described by
	/// `zipWith`.
	public static func zip<B, C, D, E, F, G, H>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>, _ h: SignalProducer<H, Error>) -> SignalProducer<(Value, B, C, D, E, F, G, H), Error> {
		return zip(a, b, c, d, e, f, g)
			.zip(with: h)
			.map(repack)
	}

	/// Zips the values of all the given producers, in the manner described by
	/// `zipWith`.
	public static func zip<B, C, D, E, F, G, H, I>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>, _ h: SignalProducer<H, Error>, _ i: SignalProducer<I, Error>) -> SignalProducer<(Value, B, C, D, E, F, G, H, I), Error> {
		return zip(a, b, c, d, e, f, g, h)
			.zip(with: i)
			.map(repack)
	}

	/// Zips the values of all the given producers, in the manner described by
	/// `zipWith`.
	public static func zip<B, C, D, E, F, G, H, I, J>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>, _ h: SignalProducer<H, Error>, _ i: SignalProducer<I, Error>, _ j: SignalProducer<J, Error>) -> SignalProducer<(Value, B, C, D, E, F, G, H, I, J), Error> {
		return zip(a, b, c, d, e, f, g, h, i)
			.zip(with: j)
			.map(repack)
	}

	/// Zips the values of all the given producers, in the manner described by
	/// `zipWith`. Will return an empty `SignalProducer` if the sequence is empty.
	public static func zip<S: Sequence>(_ producers: S) -> SignalProducer<[Value], Error>
		where S.Iterator.Element == SignalProducer<Value, Error>
	{
		var generator = producers.makeIterator()
		if let first = generator.next() {
			let initial = first.map { [$0] }
			return IteratorSequence(generator).reduce(initial) { producer, next in
				producer.zip(with: next).map { $0.0 + [$0.1] }
			}
		}

		return .empty
	}
}

extension SignalProducerProtocol {
	/// Repeat `self` a total of `count` times. In other words, start producer
	/// `count` number of times, each one after previously started producer
	/// completes.
	///
	/// - note: Repeating `1` time results in an equivalent signal producer.
	///
	/// - note: Repeating `0` times results in a producer that instantly
	///         completes.
	///
	/// - parameters:
	///   - count: Number of repetitions.
	///
	/// - returns: A signal producer start sequentially starts `self` after
	///            previously started producer completes.
	public func `repeat`(_ count: Int) -> SignalProducer<Value, Error> {
		precondition(count >= 0)

		if count == 0 {
			return .empty
		} else if count == 1 {
			return producer
		}

		return SignalProducer { observer, disposable in
			let serialDisposable = SerialDisposable()
			disposable += serialDisposable

			func iterate(_ current: Int) {
				self.startWithSignal { signal, signalDisposable in
					serialDisposable.inner = signalDisposable

					signal.observe { event in
						if case .completed = event {
							let remainingTimes = current - 1
							if remainingTimes > 0 {
								iterate(remainingTimes)
							} else {
								observer.sendCompleted()
							}
						} else {
							observer.action(event)
						}
					}
				}
			}

			iterate(count)
		}
	}

	/// Ignore failures up to `count` times.
	///
	/// - precondition: `count` must be non-negative integer.
	///
	/// - parameters:
	///   - count: Number of retries.
	///
	/// - returns: A signal producer that restarts up to `count` times.
	public func retry(upTo count: Int) -> SignalProducer<Value, Error> {
		precondition(count >= 0)

		if count == 0 {
			return producer
		} else {
			return flatMapError { _ in
				self.retry(upTo: count - 1)
			}
		}
	}

	/// Wait for completion of `self`, *then* forward all events from
	/// `replacement`. Any failure or interruption sent from `self` is
	/// forwarded immediately, in which case `replacement` will not be started,
	/// and none of its events will be be forwarded. 
	///
	/// - note: All values sent from `self` are ignored.
	///
	/// - parameters:
	///   - replacement: A producer to start when `self` completes.
	///
	/// - returns: A producer that sends events from `self` and then from
	///            `replacement` when `self` completes.
	public func then<U>(_ replacement: SignalProducer<U, Error>) -> SignalProducer<U, Error> {
		return SignalProducer<U, Error> { observer, observerDisposable in
			self.startWithSignal { signal, signalDisposable in
				observerDisposable += signalDisposable

				signal.observe { event in
					switch event {
					case let .failed(error):
						observer.send(error: error)
					case .completed:
						observerDisposable += replacement.start(observer)
					case .interrupted:
						observer.sendInterrupted()
					case .value:
						break
					}
				}
			}
		}
	}

	/// Wait for completion of `self`, *then* forward all events from
	/// `replacement`. Any failure or interruption sent from `self` is
	/// forwarded immediately, in which case `replacement` will not be started,
	/// and none of its events will be be forwarded.
	///
	/// - note: All values sent from `self` are ignored.
	///
	/// - parameters:
	///   - replacement: A producer to start when `self` completes.
	///
	/// - returns: A producer that sends events from `self` and then from
	///            `replacement` when `self` completes.
	public func then<U>(_ replacement: SignalProducer<U, NoError>) -> SignalProducer<U, Error> {
		return self.then(replacement.promoteErrors(Error.self))
	}

	/// Start the producer, then block, waiting for the first value.
	///
	/// When a single value or error is sent, the returned `Result` will
	/// represent those cases. However, when no values are sent, `nil` will be
	/// returned.
	///
	/// - returns: Result when single `value` or `failed` event is received.
	///            `nil` when no events are received.
	public func first() -> Result<Value, Error>? {
		return take(first: 1).single()
	}

	/// Start the producer, then block, waiting for events: `value` and
	/// `completed`.
	///
	/// When a single value or error is sent, the returned `Result` will
	/// represent those cases. However, when no values are sent, or when more
	/// than one value is sent, `nil` will be returned.
	///
	/// - returns: Result when single `value` or `failed` event is received.
	///            `nil` when 0 or more than 1 events are received.
	public func single() -> Result<Value, Error>? {
		let semaphore = DispatchSemaphore(value: 0)
		var result: Result<Value, Error>?

		take(first: 2).start { event in
			switch event {
			case let .value(value):
				if result != nil {
					// Move into failure state after recieving another value.
					result = nil
					return
				}
				result = .success(value)
			case let .failed(error):
				result = .failure(error)
				semaphore.signal()
			case .completed, .interrupted:
				semaphore.signal()
			}
		}

		semaphore.wait()
		return result
	}

	/// Start the producer, then block, waiting for the last value.
	///
	/// When a single value or error is sent, the returned `Result` will
	/// represent those cases. However, when no values are sent, `nil` will be
	/// returned.
	///
	/// - returns: Result when single `value` or `failed` event is received.
	///            `nil` when no events are received.
	public func last() -> Result<Value, Error>? {
		return take(last: 1).single()
	}

	/// Starts the producer, then blocks, waiting for completion.
	///
	/// When a completion or error is sent, the returned `Result` will represent
	/// those cases.
	///
	/// - returns: Result when single `completion` or `failed` event is
	///            received.
	public func wait() -> Result<(), Error> {
		return then(SignalProducer<(), Error>(value: ())).last() ?? .success(())
	}

	/// Creates a new `SignalProducer` that will multicast values emitted by
	/// the underlying producer, up to `capacity`.
	/// This means that all clients of this `SignalProducer` will see the same
	/// version of the emitted values/errors.
	///
	/// The underlying `SignalProducer` will not be started until `self` is
	/// started for the first time. When subscribing to this producer, all
	/// previous values (up to `capacity`) will be emitted, followed by any new
	/// values.
	///
	/// If you find yourself needing *the current value* (the last buffered
	/// value) you should consider using `PropertyType` instead, which, unlike
	/// this operator, will guarantee at compile time that there's always a
	/// buffered value. This operator is not recommended in most cases, as it
	/// will introduce an implicit relationship between the original client and
	/// the rest, so consider alternatives like `PropertyType`, or representing
	/// your stream using a `Signal` instead.
	///
	/// This operator is only recommended when you absolutely need to introduce
	/// a layer of caching in front of another `SignalProducer`.
	///
	/// - precondition: `capacity` must be non-negative integer.
	///
	/// - parameters:
	///   - capacity: Number of values to hold.
	///
	/// - returns: A caching producer that will hold up to last `capacity`
	///            values.
	public func replayLazily(upTo capacity: Int) -> SignalProducer<Value, Error> {
		precondition(capacity >= 0, "Invalid capacity: \(capacity)")

		// This will go "out of scope" when the returned `SignalProducer` goes
		// out of scope. This lets us know when we're supposed to dispose the
		// underlying producer. This is necessary because `struct`s don't have
		// `deinit`.
		let lifetimeToken = Lifetime.Token()
		let lifetime = Lifetime(lifetimeToken)

		let state = Atomic(ReplayState<Value, Error>(upTo: capacity))

		let start: Atomic<(() -> Void)?> = Atomic {
			// Start the underlying producer.
			self
				.take(during: lifetime)
				.start { event in
					let observers: Bag<Signal<Value, Error>.Observer>? = state.modify { state in
						defer { state.enqueue(event) }
						return state.observers
					}
					observers?.forEach { $0.action(event) }
				}
		}

		return SignalProducer { observer, disposable in
			// Don't dispose of the original producer until all observers
			// have terminated.
			disposable += { _ = lifetimeToken }

			while true {
				var result: Result<RemovalToken?, ReplayError<Value>>!
				state.modify {
					result = $0.observe(observer)
				}

				switch result! {
				case let .success(token):
					if let token = token {
						disposable += {
							state.modify {
								$0.removeObserver(using: token)
							}
						}
					}

					// Start the underlying producer if it has never been started.
					start.swap(nil)?()

					// Terminate the replay loop.
					return

				case let .failure(error):
					error.values.forEach(observer.send(value:))
				}
			}
		}
	}
}

extension SignalProducerProtocol where Value == Bool {
	/// Create a producer that computes a logical NOT in the latest values of `self`.
	///
	/// - returns: A producer that emits the logical NOT results.
	public var negated: SignalProducer<Value, Error> {
		return self.lift { $0.negated }
	}
	
	/// Create a producer that computes a logical AND between the latest values of `self`
	/// and `producer`.
	///
	/// - parameters:
	///   - producer: Producer to be combined with `self`.
	///
	/// - returns: A producer that emits the logical AND results.
	public func and(_ producer: SignalProducer<Value, Error>) -> SignalProducer<Value, Error> {
		return self.liftLeft(Signal.and)(producer)
	}
	
	/// Create a producer that computes a logical AND between the latest values of `self`
	/// and `signal`.
	///
	/// - parameters:
	///   - signal: Signal to be combined with `self`.
	///
	/// - returns: A producer that emits the logical AND results.
	public func and(_ signal: Signal<Value, Error>) -> SignalProducer<Value, Error> {
		return self.lift(Signal.and)(signal)
	}
	
	/// Create a producer that computes a logical OR between the latest values of `self`
	/// and `producer`.
	///
	/// - parameters:
	///   - producer: Producer to be combined with `self`.
	///
	/// - returns: A producer that emits the logical OR results.
	public func or(_ producer: SignalProducer<Value, Error>) -> SignalProducer<Value, Error> {
		return self.liftLeft(Signal.or)(producer)
	}
	
	/// Create a producer that computes a logical OR between the latest values of `self`
	/// and `signal`.
	///
	/// - parameters:
	///   - signal: Signal to be combined with `self`.
	///
	/// - returns: A producer that emits the logical OR results.
	public func or(_ signal: Signal<Value, Error>) -> SignalProducer<Value, Error> {
		return self.lift(Signal.or)(signal)
	}
}

/// Represents a recoverable error of an observer not being ready for an
/// attachment to a `ReplayState`, and the observer should replay the supplied
/// values before attempting to observe again.
private struct ReplayError<Value>: Error {
	/// The values that should be replayed by the observer.
	let values: [Value]
}

private struct ReplayState<Value, Error: Swift.Error> {
	let capacity: Int

	/// All cached values.
	var values: [Value] = []

	/// A termination event emitted by the underlying producer.
	///
	/// This will be nil if termination has not occurred.
	var terminationEvent: Event<Value, Error>?

	/// The observers currently attached to the caching producer, or `nil` if the
	/// caching producer was terminated.
	var observers: Bag<Signal<Value, Error>.Observer>? = Bag()

	/// The set of in-flight replay buffers.
	var replayBuffers: [ObjectIdentifier: [Value]] = [:]

	/// Initialize the replay state.
	///
	/// - parameters:
	///   - capacity: The maximum amount of values which can be cached by the
	///               replay state.
	init(upTo capacity: Int) {
		self.capacity = capacity
	}

	/// Attempt to observe the replay state.
	///
	/// - warning: Repeatedly observing the replay state with the same observer
	///            should be avoided.
	///
	/// - parameters:
	///   - observer: The observer to be registered.
	///
	/// - returns:
	///   If the observer is successfully attached, a `Result.success` with the
	///   corresponding removal token would be returned. Otherwise, a
	///   `Result.failure` with a `ReplayError` would be returned.
	mutating func observe(_ observer: Signal<Value, Error>.Observer) -> Result<RemovalToken?, ReplayError<Value>> {
		// Since the only use case is `replayLazily`, which always creates a unique
		// `Observer` for every produced signal, we can use the ObjectIdentifier of
		// the `Observer` to track them directly.
		let id = ObjectIdentifier(observer)

		switch replayBuffers[id] {
		case .none where !values.isEmpty:
			// No in-flight replay buffers was found, but the `ReplayState` has one or
			// more cached values in the `ReplayState`. The observer should replay
			// them before attempting to observe again.
			replayBuffers[id] = []
			return .failure(ReplayError(values: values))

		case let .some(buffer) where !buffer.isEmpty:
			// An in-flight replay buffer was found with one or more buffered values.
			// The observer should replay them before attempting to observe again.
			defer { replayBuffers[id] = [] }
			return .failure(ReplayError(values: buffer))

		case let .some(buffer) where buffer.isEmpty:
			// Since an in-flight but empty replay buffer was found, the observer is
			// ready to be attached to the `ReplayState`.
			replayBuffers.removeValue(forKey: id)

		default:
			// No values has to be replayed. The observer is ready to be attached to
			// the `ReplayState`.
			break
		}

		if let event = terminationEvent {
			observer.action(event)
		}

		return .success(observers?.insert(observer))
	}

	/// Enqueue the supplied event to the replay state.
	///
	/// - parameter:
	///   - event: The event to be cached.
	mutating func enqueue(_ event: Event<Value, Error>) {
		switch event {
		case let .value(value):
			for key in replayBuffers.keys {
				replayBuffers[key]!.append(value)
			}

			switch capacity {
			case 0:
				// With a capacity of zero, `state.values` can never be filled.
				break

			case 1:
				values = [value]

			default:
				values.append(value)

				let overflow = values.count - capacity
				if overflow > 0 {
					values.removeFirst(overflow)
				}
			}

		case .completed, .failed, .interrupted:
			// Disconnect all observers and prevent future attachments.
			terminationEvent = event
			observers = nil
		}
	}

	/// Remove the observer represented by the supplied token.
	///
	/// - parameters:
	///   - token: The token of the observer to be removed.
	mutating func removeObserver(using token: RemovalToken) {
		observers?.remove(using: token)
	}
}

/// Create a repeating timer of the given interval, with a reasonable default
/// leeway, sending updates on the given scheduler.
///
/// - note: This timer will never complete naturally, so all invocations of
///         `start()` must be disposed to avoid leaks.
///
/// - precondition: Interval must be non-negative number.
///
///	- note: If you plan to specify an `interval` value greater than 200,000
///			seconds, use `timer(interval:on:leeway:)` instead
///			and specify your own `leeway` value to avoid potential overflow.
///
/// - parameters:
///   - interval: An interval between invocations.
///   - scheduler: A scheduler to deliver events on.
///
/// - returns: A producer that sends `NSDate` values every `interval` seconds.
public func timer(interval: DispatchTimeInterval, on scheduler: DateScheduler) -> SignalProducer<Date, NoError> {
	// Apple's "Power Efficiency Guide for Mac Apps" recommends a leeway of
	// at least 10% of the timer interval.
	return timer(interval: interval, on: scheduler, leeway: interval * 0.1)
}

/// Creates a repeating timer of the given interval, sending updates on the
/// given scheduler.
///
/// - note: This timer will never complete naturally, so all invocations of
///         `start()` must be disposed to avoid leaks.
///
/// - precondition: Interval must be non-negative number.
///
/// - precondition: Leeway must be non-negative number.
///
/// - parameters:
///   - interval: An interval between invocations.
///   - scheduler: A scheduler to deliver events on.
///   - leeway: Interval leeway. Apple's "Power Efficiency Guide for Mac Apps"
///             recommends a leeway of at least 10% of the timer interval.
///
/// - returns: A producer that sends `NSDate` values every `interval` seconds.
public func timer(interval: DispatchTimeInterval, on scheduler: DateScheduler, leeway: DispatchTimeInterval) -> SignalProducer<Date, NoError> {
	precondition(interval.timeInterval >= 0)
	precondition(leeway.timeInterval >= 0)

	return SignalProducer { observer, compositeDisposable in
		compositeDisposable += scheduler.schedule(after: scheduler.currentDate.addingTimeInterval(interval),
		                                          interval: interval,
		                                          leeway: leeway,
		                                          action: { observer.send(value: scheduler.currentDate) })
	}
}
