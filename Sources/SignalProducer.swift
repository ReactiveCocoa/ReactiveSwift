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
	public init(_ signal: Signal<Value, Error>) {
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

	/// Create a `Signal` from `self`, pass it into the given closure, and start the
	/// associated work on the produced `Signal` as the closure returns.
	///
	/// - parameters:
	///   - setup: A closure to be invoked before the work associated with the produced
	///            `Signal` commences. Both the produced `Signal` and an interrupt handle
	///            of the signal would be passed to the closure.
	public func startWithSignal(_ setup: (_ signal: Signal<Value, Error>, _ interruptHandle: Disposable) -> Void) {
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
}

extension SignalProducer: SignalProducerProtocol {
	public var producer: SignalProducer {
		return self
	}
}

extension SignalProducer {
	/// Create a `Signal` from `self`, and observe it with the given observer.
	///
	/// - parameters:
	///   - observer: An observer to attach to the produced `Signal`.
	///
	/// - returns: A disposable to interrupt the produced `Signal`.
	@discardableResult
	public func start(_ observer: Signal<Value, Error>.Observer = .init()) -> Disposable {
		var disposable: Disposable!

		startWithSignal { signal, innerDisposable in
			signal.observe(observer)
			disposable = innerDisposable
		}

		return disposable
	}

	/// Create a `Signal` from `self`, and observe the `Signal` for all events
	/// being emitted.
	///
	/// - parameters:
	///   - action: A closure to be invoked with every event from `self`.
	///
	/// - returns: A disposable to interrupt the produced `Signal`.
	@discardableResult
	public func start(_ action: @escaping Signal<Value, Error>.Observer.Action) -> Disposable {
		return start(Signal.Observer(action))
	}

	/// Create a `Signal` from `self`, and observe the `Signal` for all values being
	/// emitted, and if any, its failure.
	///
	/// - parameters:
	///   - action: A closure to be invoked with values from `self`, or the propagated
	///             error should any `failed` event is emitted.
	///
	/// - returns: A disposable to interrupt the produced `Signal`.
	@discardableResult
	public func startWithResult(_ action: @escaping (Result<Value, Error>) -> Void) -> Disposable {
		return start(
			Signal.Observer(
				value: { action(.success($0)) },
				failed: { action(.failure($0)) }
			)
		)
	}

	/// Create a `Signal` from `self`, and observe its completion.
	///
	/// - parameters:
	///   - action: A closure to be invoked when a `completed` event is emitted.
	///
	/// - returns: A disposable to interrupt the produced `Signal`.
	@discardableResult
	public func startWithCompleted(_ action: @escaping () -> Void) -> Disposable {
		return start(Signal.Observer(completed: action))
	}
	
	/// Create a `Signal` from `self`, and observe its failure.
	///
	/// - parameters:
	///   - action: A closure to be invoked with the propagated error, should any
	///             `failed` event is emitted.
	///
	/// - returns: A disposable to interrupt the produced `Signal`.
	@discardableResult
	public func startWithFailed(_ action: @escaping (Error) -> Void) -> Disposable {
		return start(Signal.Observer(failed: action))
	}
	
	/// Create a `Signal` from `self`, and observe its interruption.
	///
	/// - parameters:
	///   - action: A closure to be invoked when an `interrupted` event is emitted.
	///
	/// - returns: A disposable to interrupt the produced `Signal`.
	@discardableResult
	public func startWithInterrupted(_ action: @escaping () -> Void) -> Disposable {
		return start(Signal.Observer(interrupted: action))
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

	/// Create a `Signal` from `self` in the manner described by `startWithSignal`, and
	/// put the interrupt handle into the given `CompositeDisposable`.
	///
	/// - parameters:
	///   - disposable: The `CompositeDisposable` the interrupt handle to be added to.
	///   - setup: A closure that accepts the produced `Signal`.
	internal func startWithSignal(interruptingBy disposable: CompositeDisposable, setup: (Signal<Value, Error>) -> Void) {
		startWithSignal { signal, interruptHandle in
			disposable += interruptHandle
			setup(signal)
		}
	}
}

extension SignalProducer where Error == NoError {
	/// Create a `Signal` from `self`, and observe the `Signal` for all values being
	/// emitted.
	///
	/// - parameters:
	///   - action: A closure to be invoked with values from the produced `Signal`.
	///
	/// - returns: A disposable to interrupt the produced `Signal`.
	@discardableResult
	public func startWithValues(_ action: @escaping (Value) -> Void) -> Disposable {
		return start(Signal.Observer(value: action))
	}
}
