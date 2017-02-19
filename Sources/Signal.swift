import Foundation
import Result

/// A push-driven stream that sends Events over time, parameterized by the type
/// of values being sent (`Value`) and the type of failure that can occur
/// (`Error`). If no failures should be possible, NoError can be specified for
/// `Error`.
///
/// An observer of a Signal will see the exact same sequence of events as all
/// other observers. In other words, events will be sent to all observers at the
/// same time.
///
/// Signals are generally used to represent event streams that are already “in
/// progress,” like notifications, user input, etc. To represent streams that
/// must first be _started_, see the SignalProducer type.
///
/// A Signal is kept alive until either of the following happens:
///    1. its input observer receives a terminating event; or
///    2. it has no active observers, and is not being retained.
public final class Signal<Value, Error: Swift.Error> {
	public typealias Observer = ReactiveSwift.Observer<Value, Error>

	/// The disposable returned by the signal generator. It would be disposed of
	/// when the signal terminates.
	private var generatorDisposable: Disposable?

	/// The state of the signal.
	///
 	/// `state` synchronizes using Read-Copy-Update. Reads on the event delivery
	/// routine are thus wait-free. But modifications, e.g. inserting observers,
	/// still have to be serialized, and are required not to mutate in place.
	///
	/// This suits `Signal` as reads to `status` happens on the critical path of
	/// event delivery, while observers bag manipulation or termination generally
	/// has a constant occurrence.
	///
	/// As `SignalState` is a packed object reference (a tagged pointer) that is
	/// naturally aligned, reads to are guaranteed to be atomic on all supported
	/// hardware architectures of Swift (ARM and x86).
	private var state: SignalState<Value, Error>

	/// Used to ensure that state updates are serialized.
	private let updateLock: NSLock

	/// Used to ensure that events are serialized during delivery to observers.
	private let sendLock: NSLock

	/// Initialize a Signal that will immediately invoke the given generator,
	/// then forward events sent to the given observer.
	///
	/// - note: The disposable returned from the closure will be automatically
	///         disposed if a terminating event is sent to the observer. The
	///         Signal itself will remain alive until the observer is released.
	///
	/// - parameters:
	///   - generator: A closure that accepts an implicitly created observer
	///                that will act as an event emitter for the signal.
	public init(_ generator: (Observer) -> Disposable?) {
		state = .alive(AliveState())
		updateLock = NSLock()
		updateLock.name = "org.reactivecocoa.ReactiveSwift.Signal.updateLock"
		sendLock = NSLock()
		sendLock.name = "org.reactivecocoa.ReactiveSwift.Signal.sendLock"

		let observer = Observer { [weak self] event in
			guard let signal = self else {
				return
			}

			// Thread Safety Notes on `Signal.state`.
			//
			// - Check if the signal is at a specific state.
			//
			//   Read directly.
			//
			// - Deliver `value` events with the alive state.
			//
			//   `sendLock` must be acquired.
			//
			// - Replace the alive state with another.
			//   (e.g. observers bag manipulation)
			//
			//   `updateLock` must be acquired.
			//
			// - Transition from `alive` to `terminating` as a result of receiving
			//   a termination event.
			//
			//   `updateLock` must be acquired, and should fail gracefully if the
			//   signal has terminated.
			//
			// - Check if the signal is terminating. If it is, invoke `tryTerminate`
			//   which transitions the state from `terminating` to `terminated`, and
			//   delivers the termination event.
			//
			//   Both `sendLock` and `updateLock` must be acquired. The check can be
			//   relaxed, but the state must be checked again after the locks are
			//   acquired. Fail gracefully if the state has changed since the relaxed
			//   read, i.e. a concurrent sender has already handled the termination
			//   event.
			//
			// Exploiting the relaxation of reads, please note that false positives
			// are intentionally allowed in the `terminating` checks below. As a
			// result, normal event deliveries need not acquire `updateLock`.
			// Nevertheless, this should not cause the termination event being
			// sent multiple times, since `tryTerminate` would not respond to false
			// positives.

			/// Try to terminate the signal.
			///
			/// If the signal is alive or has terminated, it fails gracefully. In
			/// other words, calling this method as a result of a false positive
			/// `terminating` check is permitted.
			///
			/// - note: The `updateLock` would be acquired.
			///
			/// - returns: `true` if the attempt succeeds. `false` otherwise.
			@inline(__always)
			func tryTerminate() -> Bool {
				// Acquire `updateLock`. If the termination has still not yet been
				// handled, take it over and bump the status to `terminated`.
				signal.updateLock.lock()

				if case let .terminating(state) = signal.state {
					signal.state = .terminated
					signal.updateLock.unlock()

					for observer in state.observers {
						observer.action(state.event)
					}

					return true
				}

				signal.updateLock.unlock()
				return false
			}

			if event.isTerminating {
				// Recursive events are disallowed for `value` events, but are permitted
				// for termination events. Specifically:
				//
				// - `interrupted`
				// It can inadvertently be sent by downstream consumers as part of the
				// `SignalProducer` mechanics.
				//
				// - `completed`
				// If a downstream consumer weakly references an object, invocation of
				// such consumer may cause a race condition with its weak retain against
				// the last strong release of the object. If the `Lifetime` of the
				// object is being referenced by an upstream `take(during:)`, a
				// signal recursion might occur.
				//
				// So we would treat termination events specially. If it happens to
				// occur while the `sendLock` is acquired, the observer call-out and
				// the disposal would be delegated to the current sender, or
				// occasionally one of the senders waiting on `sendLock`.
				signal.updateLock.lock()

				if case let .alive(state) = signal.state {
					let newSnapshot = TerminatingState(observers: state.observers,
					                                   event: event)
					signal.state = .terminating(newSnapshot)
					signal.updateLock.unlock()

					if signal.sendLock.try() {
						// Check whether the terminating state has been handled by a
						// concurrent sender. If not, handle it.
						let shouldDispose = tryTerminate()
						signal.sendLock.unlock()

						if shouldDispose {
							signal.swapDisposable()?.dispose()
						}
					}
				} else {
					signal.updateLock.unlock()
				}
			} else {
				var shouldDispose = false

				// The `terminating` status check is performed twice for two different
				// purposes:
				//
				// 1. Within the main protected section
				//    It guarantees that a recursive termination event sent by a
				//    downstream consumer, is immediately processed and need not compete
				//    with concurrent pending senders (if any).
				//
				//    Termination events sent concurrently may also be caught here, but
				//    not necessarily all of them due to data races.
				//
				// 2. After the main protected section
				//    It ensures the termination event sent concurrently that are not
				//    caught by (1) due to data races would still be processed.
				//
				// The related PR on the race conditions:
				// https://github.com/ReactiveCocoa/ReactiveSwift/pull/112

				signal.sendLock.lock()
				// Start of the main protected section.

				if case let .alive(state) = signal.state {
					for observer in state.observers {
						observer.action(event)
					}

					// Check if the status has been bumped to `terminating` due to a
					// concurrent or a recursive termination event.
					if case .terminating = signal.state {
						shouldDispose = tryTerminate()
					}
				}

				// End of the main protected section.
				signal.sendLock.unlock()

				// Check if the status has been bumped to `terminating` due to a
				// concurrent termination event that has not been caught in the main
				// protected section.
				if !shouldDispose, case .terminating = signal.state {
					signal.sendLock.lock()
					shouldDispose = tryTerminate()
					signal.sendLock.unlock()
				}

				if shouldDispose {
					// Dispose only after notifying observers, so disposal
					// logic is consistently the last thing to run.
					signal.swapDisposable()?.dispose()
				}
			}
		}

		generatorDisposable = generator(observer)
	}

	/// Swap the generator disposable with `nil`.
	///
	/// - returns:
	///   The generator disposable, or `nil` if it has been disposed of.
	private func swapDisposable() -> Disposable? {
		if let d = generatorDisposable {
			generatorDisposable = nil
			return d
		}
		return nil
	}

	deinit {
		// A signal can deinitialize only when it is not retained and has no
		// active observers. So `state` need not be swapped.
		swapDisposable()?.dispose()
	}

	/// A Signal that never sends any events to its observers.
	public static var never: Signal {
		return self.init { _ in nil }
	}

	/// A Signal that completes immediately without emitting any value.
	public static var empty: Signal {
		return self.init { observer in
			observer.sendCompleted()
			return nil
		}
	}

	/// Create a `Signal` that will be controlled by sending events to an
	/// input observer.
	///
	/// - note: The `Signal` will remain alive until a terminating event is sent
	///         to the input observer, or until it has no observers and there
	///         are no strong references to it.
	///
	/// - parameters:
	///   - disposable: An optional disposable to associate with the signal, and
	///                 to be disposed of when the signal terminates.
	///
	/// - returns: A tuple of `output: Signal`, the output end of the pipe,
	///            and `input: Observer`, the input end of the pipe.
	public static func pipe(disposable: Disposable? = nil) -> (output: Signal, input: Observer) {
		var observer: Observer!
		let signal = self.init { innerObserver in
			observer = innerObserver
			return disposable
		}

		return (signal, observer)
	}

	/// Observe the Signal by sending any future events to the given observer.
	///
	/// - note: If the Signal has already terminated, the observer will
	///         immediately receive an `interrupted` event.
	///
	/// - parameters:
	///   - observer: An observer to forward the events to.
	///
	/// - returns: A `Disposable` which can be used to disconnect the observer,
	///            or `nil` if the signal has already terminated.
	@discardableResult
	public func observe(_ observer: Observer) -> Disposable? {
		var token: RemovalToken?
		updateLock.lock()
		if case let .alive(snapshot) = state {
			var observers = snapshot.observers
			token = observers.insert(observer)
			state = .alive(AliveState(observers: observers, retaining: self))
		}
		updateLock.unlock()

		if let token = token {
			return ActionDisposable { [weak self] in
				if let s = self {
					s.updateLock.lock()

					if case let .alive(snapshot) = s.state {
						var observers = snapshot.observers
						observers.remove(using: token)

						// Ensure the old signal state snapshot does not deinitialize before
						// `updateLock` is released. Otherwise, it might result in a
						// deadlock in cases where a `Signal` legitimately receives terminal
						// events recursively as a result of the deinitialization of the
						// snapshot.
						withExtendedLifetime(snapshot) {
							s.state = .alive(AliveState(observers: observers,
							                            retaining: observers.isEmpty ? nil : self))
							s.updateLock.unlock()
						}
					} else {
						s.updateLock.unlock()
					}
				}
			}
		} else {
			observer.sendInterrupted()
			return nil
		}
	}
}

/// The state of a `Signal`.
///
/// `SignalState` is guaranteed to be laid out as a tagged pointer by the Swift
/// compiler in the support targets of the Swift 3.0.1 ABI.
///
/// The Swift compiler has also an optimization for enums with payloads that are
/// all reference counted, and at most one no-payload case.
private enum SignalState<Value, Error: Swift.Error> {
	/// The `Signal` is alive.
	case alive(AliveState<Value, Error>)

	/// The `Signal` has received a termination event, and is about to be
	/// terminated.
	case terminating(TerminatingState<Value, Error>)

	/// The `Signal` has terminated.
	case terminated
}

// As the amount of state would definitely span over a cache line,
// `AliveState` and `TerminatingState` is set to be a reference type so
// that we can atomically update the reference instead.
//
// Note that in-place mutation should not be introduced to `AliveState` and
// `TerminatingState`. Copy the states and create a new instance.

/// The state of a `Signal` that is alive. It contains a bag of observers and
/// an optional self-retaining reference.
private final class AliveState<Value, Error: Swift.Error> {
	/// The observers of the `Signal`.
	fileprivate let observers: Bag<Signal<Value, Error>.Observer>

	/// A self-retaining reference. It is set when there are one or more active
	/// observers.
	fileprivate let retaining: Signal<Value, Error>?

	/// Create an alive state.
	///
	/// - parameters:
	///   - observers: The latest bag of observers.
	///   - retaining: The self-retaining reference of the `Signal`, if necessary.
	init(observers: Bag<Signal<Value, Error>.Observer> = Bag(), retaining: Signal<Value, Error>? = nil) {
		self.observers = observers
		self.retaining = retaining
	}
}

/// The state of a terminating `Signal`. It contains a bag of observers and the
/// termination event.
private final class TerminatingState<Value, Error: Swift.Error> {
	/// The observers of the `Signal`.
	fileprivate let observers: Bag<Signal<Value, Error>.Observer>

	///  The termination event.
	fileprivate let event: Event<Value, Error>

	/// Create a terminating state.
	///
	/// - parameters:
	///   - observers: The latest bag of observers.
	///   - event: The termination event.
	init(observers: Bag<Signal<Value, Error>.Observer>, event: Event<Value, Error>) {
		self.observers = observers
		self.event = event
	}
}

/// A protocol used to constraint `Signal` operators.
public protocol SignalProtocol {
	/// The type of values being sent on the signal.
	associatedtype Value

	/// The type of error that can occur on the signal. If errors aren't
	/// possible then `NoError` can be used.
	associatedtype Error: Swift.Error

	/// Extracts a signal from the receiver.
	var signal: Signal<Value, Error> { get }

	/// Observes the Signal by sending any future events to the given observer.
	@discardableResult
	func observe(_ observer: Signal<Value, Error>.Observer) -> Disposable?
}

extension Signal: SignalProtocol {
	public var signal: Signal {
		return self
	}
}

extension SignalProtocol {
	/// Convenience override for observe(_:) to allow trailing-closure style
	/// invocations.
	///
	/// - parameters:
	///   - action: A closure that will accept an event of the signal
	///
	/// - returns: An optional `Disposable` which can be used to stop the
	///            invocation of the callback. Disposing of the Disposable will
	///            have no effect on the Signal itself.
	@discardableResult
	public func observe(_ action: @escaping Signal<Value, Error>.Observer.Action) -> Disposable? {
		return observe(Observer(action))
	}

	/// Observe the `Signal` by invoking the given callback when `value` or
	/// `failed` event are received.
	///
	/// - parameters:
	///   - result: A closure that accepts instance of `Result<Value, Error>`
	///             enum that contains either a `.success(Value)` or
	///             `.failure<Error>` case.
	///
	/// - returns: An optional `Disposable` which can be used to stop the
	///            invocation of the callback. Disposing of the Disposable will
	///            have no effect on the Signal itself.
	@discardableResult
	public func observeResult(_ result: @escaping (Result<Value, Error>) -> Void) -> Disposable? {
		return observe(
			Observer(
				value: { result(.success($0)) },
				failed: { result(.failure($0)) }
			)
		)
	}

	/// Observe the `Signal` by invoking the given callback when a `completed`
	/// event is received.
	///
	/// - parameters:
	///   - completed: A closure that is called when `completed` event is
	///                received.
	///
	/// - returns: An optional `Disposable` which can be used to stop the
	///            invocation of the callback. Disposing of the Disposable will
	///            have no effect on the Signal itself.
	@discardableResult
	public func observeCompleted(_ completed: @escaping () -> Void) -> Disposable? {
		return observe(Observer(completed: completed))
	}
	
	/// Observe the `Signal` by invoking the given callback when a `failed` 
	/// event is received.
	///
	/// - parameters:
	///   - error: A closure that is called when failed event is received. It
	///            accepts an error parameter.
	///
	/// Returns a Disposable which can be used to stop the invocation of the
	/// callback. Disposing of the Disposable will have no effect on the Signal
	/// itself.
	@discardableResult
	public func observeFailed(_ error: @escaping (Error) -> Void) -> Disposable? {
		return observe(Observer(failed: error))
	}
	
	/// Observe the `Signal` by invoking the given callback when an 
	/// `interrupted` event is received. If the Signal has already terminated, 
	/// the callback will be invoked immediately.
	///
	/// - parameters:
	///   - interrupted: A closure that is invoked when `interrupted` event is
	///                  received
	///
	/// - returns: An optional `Disposable` which can be used to stop the
	///            invocation of the callback. Disposing of the Disposable will
	///            have no effect on the Signal itself.
	@discardableResult
	public func observeInterrupted(_ interrupted: @escaping () -> Void) -> Disposable? {
		return observe(Observer(interrupted: interrupted))
	}
}

extension SignalProtocol where Error == NoError {
	/// Observe the Signal by invoking the given callback when `value` events are
	/// received.
	///
	/// - parameters:
	///   - value: A closure that accepts a value when `value` event is received.
	///
	/// - returns: An optional `Disposable` which can be used to stop the
	///            invocation of the callback. Disposing of the Disposable will
	///            have no effect on the Signal itself.
	@discardableResult
	public func observeValues(_ value: @escaping (Value) -> Void) -> Disposable? {
		return observe(Observer(value: value))
	}
}

extension SignalProtocol {
	/// Map each value in the signal to a new value.
	///
	/// - parameters:
	///   - transform: A closure that accepts a value from the `value` event and
	///                returns a new value.
	///
	/// - returns: A signal that will send new values.
	public func map<U>(_ transform: @escaping (Value) -> U) -> Signal<U, Error> {
		return Signal { observer in
			return self.observe { event in
				observer.action(event.map(transform))
			}
		}
	}

	/// Map errors in the signal to a new error.
	///
	/// - parameters:
	///   - transform: A closure that accepts current error object and returns
	///                a new type of error object.
	///
	/// - returns: A signal that will send new type of errors.
	public func mapError<F>(_ transform: @escaping (Error) -> F) -> Signal<Value, F> {
		return Signal { observer in
			return self.observe { event in
				observer.action(event.mapError(transform))
			}
		}
	}

	/// Maps each value in the signal to a new value, lazily evaluating the
	/// supplied transformation on the specified scheduler.
	///
	/// - important: Unlike `map`, there is not a 1-1 mapping between incoming
	///              values, and values sent on the returned signal. If
	///              `scheduler` has not yet scheduled `transform` for
	///              execution, then each new value will replace the last one as
	///              the parameter to `transform` once it is finally executed.
	///
	/// - parameters:
	///   - transform: The closure used to obtain the returned value from this
	///                signal's underlying value.
	///
	/// - returns: A signal that sends values obtained using `transform` as this 
	///            signal sends values.
	public func lazyMap<U>(on scheduler: Scheduler, transform: @escaping (Value) -> U) -> Signal<U, Error> {
		return flatMap(.latest) { value in
			return SignalProducer({ transform(value) })
				.start(on: scheduler)
		}
	}

	/// Preserve only the values of the signal that pass the given predicate.
	///
	/// - parameters:
	///   - predicate: A closure that accepts value and returns `Bool` denoting
	///                whether value has passed the test.
	///
	/// - returns: A signal that will send only the values passing the given
	///            predicate.
	public func filter(_ predicate: @escaping (Value) -> Bool) -> Signal<Value, Error> {
		return Signal { observer in
			return self.observe { (event: Event<Value, Error>) -> Void in
				guard let value = event.value else {
					observer.action(event)
					return
				}

				if predicate(value) {
					observer.send(value: value)
				}
			}
		}
	}
	
	/// Applies `transform` to values from `signal` and forwards values with non `nil` results unwrapped.
	/// - parameters:
	///   - transform: A closure that accepts a value from the `value` event and
	///                returns a new optional value.
	///
	/// - returns: A signal that will send new values, that are non `nil` after the transformation.
	public func filterMap<U>(_ transform: @escaping (Value) -> U?) -> Signal<U, Error> {
		return Signal { observer in
			return self.observe { (event: Event<Value, Error>) -> Void in
				switch event {
				case let .value(value):
					if let mapped = transform(value) {
						observer.send(value: mapped)
					}
				case let .failed(error):
					observer.send(error: error)
				case .completed:
					observer.sendCompleted()
				case .interrupted:
					observer.sendInterrupted()
				}
			}
		}
	}
}

extension SignalProtocol where Value: OptionalProtocol {
	/// Unwrap non-`nil` values and forward them on the returned signal, `nil`
	/// values are dropped.
	///
	/// - returns: A signal that sends only non-nil values.
	public func skipNil() -> Signal<Value.Wrapped, Error> {
		return filterMap { $0.optional }
	}
}

extension SignalProtocol {
	/// Take up to `n` values from the signal and then complete.
	///
	/// - precondition: `count` must be non-negative number.
	///
	/// - parameters:
	///   - count: A number of values to take from the signal.
	///
	/// - returns: A signal that will yield the first `count` values from `self`
	public func take(first count: Int) -> Signal<Value, Error> {
		precondition(count >= 0)

		return Signal { observer in
			if count == 0 {
				observer.sendCompleted()
				return nil
			}

			var taken = 0

			return self.observe { event in
				guard let value = event.value else {
					observer.action(event)
					return
				}

				if taken < count {
					taken += 1
					observer.send(value: value)
				}

				if taken == count {
					observer.sendCompleted()
				}
			}
		}
	}
}

/// A reference type which wraps an array to auxiliate the collection of values
/// for `collect` operator.
private final class CollectState<Value> {
	var values: [Value] = []

	/// Collects a new value.
	func append(_ value: Value) {
		values.append(value)
	}

	/// Check if there are any items remaining.
	///
	/// - note: This method also checks if there weren't collected any values
	///         and, in that case, it means an empty array should be sent as the
	///         result of collect.
	var isEmpty: Bool {
		/// We use capacity being zero to determine if we haven't collected any
		/// value since we're keeping the capacity of the array to avoid
		/// unnecessary and expensive allocations). This also guarantees
		/// retro-compatibility around the original `collect()` operator.
		return values.isEmpty && values.capacity > 0
	}

	/// Removes all values previously collected if any.
	func flush() {
		// Minor optimization to avoid consecutive allocations. Can
		// be useful for sequences of regular or similar size and to
		// track if any value was ever collected.
		values.removeAll(keepingCapacity: true)
	}
}

extension SignalProtocol {
	/// Collect all values sent by the signal then forward them as a single
	/// array and complete.
	///
	/// - note: When `self` completes without collecting any value, it will send
	///         an empty array of values.
	///
	/// - returns: A signal that will yield an array of values when `self`
	///            completes.
	public func collect() -> Signal<[Value], Error> {
		return collect { _,_ in false }
	}

	/// Collect at most `count` values from `self`, forward them as a single
	/// array and complete.
	///
	/// - note: When the count is reached the array is sent and the signal
	///         starts over yielding a new array of values.
	///
	/// - note: When `self` completes any remaining values will be sent, the
	///         last array may not have `count` values. Alternatively, if were
	///         not collected any values will sent an empty array of values.
	///
	/// - precondition: `count` should be greater than zero.
	///
	public func collect(count: Int) -> Signal<[Value], Error> {
		precondition(count > 0)
		return collect { values in values.count == count }
	}

	/// Collect values that pass the given predicate then forward them as a
	/// single array and complete.
	///
	/// - note: When `self` completes any remaining values will be sent, the
	///         last array may not match `predicate`. Alternatively, if were not
	///         collected any values will sent an empty array of values.
	///
	/// ````
	/// let (signal, observer) = Signal<Int, NoError>.pipe()
	///
	/// signal
	///     .collect { values in values.reduce(0, combine: +) == 8 }
	///     .observeValues { print($0) }
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
	/// - returns: A signal that collects values passing the predicate and, when
	///            `self` completes, forwards them as a single array and
	///            complets.
	public func collect(_ predicate: @escaping (_ values: [Value]) -> Bool) -> Signal<[Value], Error> {
		return Signal { observer in
			let state = CollectState<Value>()

			return self.observe { event in
				switch event {
				case let .value(value):
					state.append(value)
					if predicate(state.values) {
						observer.send(value: state.values)
						state.flush()
					}
				case .completed:
					if !state.isEmpty {
						observer.send(value: state.values)
					}
					observer.sendCompleted()
				case let .failed(error):
					observer.send(error: error)
				case .interrupted:
					observer.sendInterrupted()
				}
			}
		}
	}

	/// Repeatedly collect an array of values up to a matching `value` value.
	/// Then forward them as single array and wait for value events.
	///
	/// - note: When `self` completes any remaining values will be sent, the
	///         last array may not match `predicate`. Alternatively, if no
	///         values were collected an empty array will be sent.
	///
	/// ````
	/// let (signal, observer) = Signal<Int, NoError>.pipe()
	///
	/// signal
	///     .collect { values, value in value == 7 }
	///     .observeValues { print($0) }
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
	///                (`value`) is not included in `values` and will be the
	///                start of the next array of values if the predicate
	///                returns `true`.
	///
	/// - returns: A signal that will yield an array of values based on a
	///            predicate which matches the values collected and the next
	///            value.
	public func collect(_ predicate: @escaping (_ values: [Value], _ value: Value) -> Bool) -> Signal<[Value], Error> {
		return Signal { observer in
			let state = CollectState<Value>()

			return self.observe { event in
				switch event {
				case let .value(value):
					if predicate(state.values, value) {
						observer.send(value: state.values)
						state.flush()
					}
					state.append(value)
				case .completed:
					if !state.isEmpty {
						observer.send(value: state.values)
					}
					observer.sendCompleted()
				case let .failed(error):
					observer.send(error: error)
				case .interrupted:
					observer.sendInterrupted()
				}
			}
		}
	}

	/// Forward all events onto the given scheduler, instead of whichever
	/// scheduler they originally arrived upon.
	///
	/// - parameters:
	///   - scheduler: A scheduler to deliver events on.
	///
	/// - returns: A signal that will yield `self` values on provided scheduler.
	public func observe(on scheduler: Scheduler) -> Signal<Value, Error> {
		return Signal { observer in
			return self.observe { event in
				scheduler.schedule {
					observer.action(event)
				}
			}
		}
	}
}

private final class CombineLatestState<Value> {
	var latestValue: Value?
	var isCompleted = false
}

extension SignalProtocol {
	private func observeWithStates<U>(_ signalState: CombineLatestState<Value>, _ otherState: CombineLatestState<U>, _ lock: NSLock, _ observer: Signal<(), Error>.Observer) -> Disposable? {
		return self.observe { event in
			switch event {
			case let .value(value):
				lock.lock()

				signalState.latestValue = value
				if otherState.latestValue != nil {
					observer.send(value: ())
				}

				lock.unlock()

			case let .failed(error):
				observer.send(error: error)

			case .completed:
				lock.lock()

				signalState.isCompleted = true
				if otherState.isCompleted {
					observer.sendCompleted()
				}

				lock.unlock()

			case .interrupted:
				observer.sendInterrupted()
			}
		}
	}

	/// Combine the latest value of the receiver with the latest value from the
	/// given signal.
	///
	/// - note: The returned signal will not send a value until both inputs have
	///         sent at least one value each.
	///
	/// - note: If either signal is interrupted, the returned signal will also
	///         be interrupted.
	///
	/// - note: The returned signal will not complete until both inputs
	///         complete.
	///
	/// - parameters:
	///   - otherSignal: A signal to combine `self`'s value with.
	///
	/// - returns: A signal that will yield a tuple containing values of `self`
	///            and given signal.
	public func combineLatest<U>(with other: Signal<U, Error>) -> Signal<(Value, U), Error> {
		return Signal { observer in
			let lock = NSLock()
			lock.name = "org.reactivecocoa.ReactiveSwift.combineLatestWith"

			let signalState = CombineLatestState<Value>()
			let otherState = CombineLatestState<U>()

			let onBothValue = {
				observer.send(value: (signalState.latestValue!, otherState.latestValue!))
			}

			let observer = Signal<(), Error>.Observer(value: onBothValue, failed: observer.send(error:), completed: observer.sendCompleted, interrupted: observer.sendInterrupted)

			let disposable = CompositeDisposable()
			disposable += self.observeWithStates(signalState, otherState, lock, observer)
			disposable += other.observeWithStates(otherState, signalState, lock, observer)
			
			return disposable
		}
	}

	/// Delay `value` and `completed` events by the given interval, forwarding
	/// them on the given scheduler.
	///
	/// - note: failed and `interrupted` events are always scheduled
	///         immediately.
	///
	/// - precondition: `interval` must be non-negative number.
	///
	/// - parameters:
	///   - interval: Interval to delay `value` and `completed` events by.
	///   - scheduler: A scheduler to deliver delayed events on.
	///
	/// - returns: A signal that will delay `value` and `completed` events and
	///            will yield them on given scheduler.
	public func delay(_ interval: TimeInterval, on scheduler: DateScheduler) -> Signal<Value, Error> {
		precondition(interval >= 0)

		return Signal { observer in
			return self.observe { event in
				switch event {
				case .failed, .interrupted:
					scheduler.schedule {
						observer.action(event)
					}

				case .value, .completed:
					let date = scheduler.currentDate.addingTimeInterval(interval)
					scheduler.schedule(after: date) {
						observer.action(event)
					}
				}
			}
		}
	}

	/// Skip first `count` number of values then act as usual.
	///
	/// - precondition: `count` must be non-negative number.
	///
	/// - parameters:
	///   - count: A number of values to skip.
	///
	/// - returns:  A signal that will skip the first `count` values, then
	///             forward everything afterward.
	public func skip(first count: Int) -> Signal<Value, Error> {
		precondition(count >= 0)

		if count == 0 {
			return signal
		}

		return Signal { observer in
			var skipped = 0

			return self.observe { event in
				if case .value = event, skipped < count {
					skipped += 1
				} else {
					observer.action(event)
				}
			}
		}
	}

	/// Treat all Events from `self` as plain values, allowing them to be
	/// manipulated just like any other value.
	///
	/// In other words, this brings Events “into the monad”.
	///
	/// - note: When a Completed or Failed event is received, the resulting
	///         signal will send the Event itself and then complete. When an
	///         Interrupted event is received, the resulting signal will send
	///         the Event itself and then interrupt.
	///
	/// - returns: A signal that sends events as its values.
	public func materialize() -> Signal<Event<Value, Error>, NoError> {
		return Signal { observer in
			return self.observe { event in
				observer.send(value: event)

				switch event {
				case .interrupted:
					observer.sendInterrupted()

				case .completed, .failed:
					observer.sendCompleted()

				case .value:
					break
				}
			}
		}
	}
}

extension SignalProtocol where Value: EventProtocol, Error == NoError {
	/// Translate a signal of `Event` _values_ into a signal of those events
	/// themselves.
	///
	/// - returns: A signal that sends values carried by `self` events.
	public func dematerialize() -> Signal<Value.Value, Value.Error> {
		return Signal<Value.Value, Value.Error> { observer in
			return self.observe { event in
				switch event {
				case let .value(innerEvent):
					observer.action(innerEvent.event)

				case .failed:
					fatalError("NoError is impossible to construct")

				case .completed:
					observer.sendCompleted()

				case .interrupted:
					observer.sendInterrupted()
				}
			}
		}
	}
}

extension SignalProtocol {
	/// Inject side effects to be performed upon the specified signal events.
	///
	/// - parameters:
	///   - event: A closure that accepts an event and is invoked on every
	///            received event.
	///   - failed: A closure that accepts error object and is invoked for
	///             failed event.
	///   - completed: A closure that is invoked for `completed` event.
	///   - interrupted: A closure that is invoked for `interrupted` event.
	///   - terminated: A closure that is invoked for any terminating event.
	///   - disposed: A closure added as disposable when signal completes.
	///   - value: A closure that accepts a value from `value` event.
	///
	/// - returns: A signal with attached side-effects for given event cases.
	public func on(
		event: ((Event<Value, Error>) -> Void)? = nil,
		failed: ((Error) -> Void)? = nil,
		completed: (() -> Void)? = nil,
		interrupted: (() -> Void)? = nil,
		terminated: (() -> Void)? = nil,
		disposed: (() -> Void)? = nil,
		value: ((Value) -> Void)? = nil
	) -> Signal<Value, Error> {
		return Signal { observer in
			let disposable = CompositeDisposable()

			_ = disposed.map(disposable.add)

			disposable += signal.observe { receivedEvent in
				event?(receivedEvent)

				switch receivedEvent {
				case let .value(v):
					value?(v)

				case let .failed(error):
					failed?(error)

				case .completed:
					completed?()

				case .interrupted:
					interrupted?()
				}

				if receivedEvent.isTerminating {
					terminated?()
				}

				observer.action(receivedEvent)
			}

			return disposable
		}
	}
}

private struct SampleState<Value> {
	var latestValue: Value? = nil
	var isSignalCompleted: Bool = false
	var isSamplerCompleted: Bool = false
}

extension SignalProtocol {
	/// Forward the latest value from `self` with the value from `sampler` as a
	/// tuple, only when`sampler` sends a `value` event.
	///
	/// - note: If `sampler` fires before a value has been observed on `self`, 
	///         nothing happens.
	///
	/// - parameters:
	///   - sampler: A signal that will trigger the delivery of `value` event
	///              from `self`.
	///
	/// - returns: A signal that will send values from `self` and `sampler`, 
	///            sampled (possibly multiple times) by `sampler`, then complete
	///            once both input signals have completed, or interrupt if
	///            either input signal is interrupted.
	public func sample<T>(with sampler: Signal<T, NoError>) -> Signal<(Value, T), Error> {
		return Signal { observer in
			let state = Atomic(SampleState<Value>())
			let disposable = CompositeDisposable()

			disposable += self.observe { event in
				switch event {
				case let .value(value):
					state.modify {
						$0.latestValue = value
					}

				case let .failed(error):
					observer.send(error: error)

				case .completed:
					let shouldComplete: Bool = state.modify {
						$0.isSignalCompleted = true
						return $0.isSamplerCompleted
					}
					
					if shouldComplete {
						observer.sendCompleted()
					}

				case .interrupted:
					observer.sendInterrupted()
				}
			}
			
			disposable += sampler.observe { event in
				switch event {
				case .value(let samplerValue):
					if let value = state.value.latestValue {
						observer.send(value: (value, samplerValue))
					}

				case .completed:
					let shouldComplete: Bool = state.modify {
						$0.isSamplerCompleted = true
						return $0.isSignalCompleted
					}
					
					if shouldComplete {
						observer.sendCompleted()
					}

				case .interrupted:
					observer.sendInterrupted()

				case .failed:
					break
				}
			}

			return disposable
		}
	}
	
	/// Forward the latest value from `self` whenever `sampler` sends a `value`
	/// event.
	///
	/// - note: If `sampler` fires before a value has been observed on `self`, 
	///         nothing happens.
	///
	/// - parameters:
	///   - sampler: A signal that will trigger the delivery of `value` event
	///              from `self`.
	///
	/// - returns: A signal that will send values from `self`, sampled (possibly
	///            multiple times) by `sampler`, then complete once both input
	///            signals have completed, or interrupt if either input signal
	///            is interrupted.
	public func sample(on sampler: Signal<(), NoError>) -> Signal<Value, Error> {
		return sample(with: sampler)
			.map { $0.0 }
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
	public func withLatest<U>(from samplee: Signal<U, NoError>) -> Signal<(Value, U), Error> {
		return Signal { observer in
			let state = Atomic<U?>(nil)
			let disposable = CompositeDisposable()

			disposable += samplee.observeValues { value in
				state.value = value
			}

			disposable += self.observe { event in
				switch event {
				case let .value(value):
					if let value2 = state.value {
						observer.send(value: (value, value2))
					}
				case .completed:
					observer.sendCompleted()
				case let .failed(error):
					observer.send(error: error)
				case .interrupted:
					observer.sendInterrupted()
				}
			}

			return disposable
		}
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
	public func withLatest<U>(from samplee: SignalProducer<U, NoError>) -> Signal<(Value, U), Error> {
		return Signal { observer in
			let d = CompositeDisposable()
			samplee.startWithSignal { signal, disposable in
				d += disposable
				d += self.withLatest(from: signal).observe(observer)
			}
			return d
		}
	}
}

extension SignalProtocol {
	/// Forwards events from `self` until `lifetime` ends, at which point the
	/// returned signal will complete.
	///
	/// - parameters:
	///   - lifetime: A lifetime whose `ended` signal will cause the returned
	///               signal to complete.
	///
	/// - returns: A signal that will deliver events until `lifetime` ends.
	public func take(during lifetime: Lifetime) -> Signal<Value, Error> {
		return Signal { observer in
			let disposable = CompositeDisposable()
			disposable += self.observe(observer)
			disposable += lifetime.observeEnded(observer.sendCompleted)
			return disposable
		}
	}

	/// Forward events from `self` until `trigger` sends a `value` or
	/// `completed` event, at which point the returned signal will complete.
	///
	/// - parameters:
	///   - trigger: A signal whose `value` or `completed` events will stop the
	///              delivery of `value` events from `self`.
	///
	/// - returns: A signal that will deliver events until `trigger` sends
	///            `value` or `completed` events.
	public func take(until trigger: Signal<(), NoError>) -> Signal<Value, Error> {
		return Signal { observer in
			let disposable = CompositeDisposable()
			disposable += self.observe(observer)

			disposable += trigger.observe { event in
				switch event {
				case .value, .completed:
					observer.sendCompleted()

				case .failed, .interrupted:
					break
				}
			}

			return disposable
		}
	}

	/// Do not forward any values from `self` until `trigger` sends a `value` or
	/// `completed` event, at which point the returned signal behaves exactly
	/// like `signal`.
	///
	/// - parameters:
	///   - trigger: A signal whose `value` or `completed` events will start the
	///              deliver of events on `self`.
	///
	/// - returns: A signal that will deliver events once the `trigger` sends
	///            `value` or `completed` events.
	public func skip(until trigger: Signal<(), NoError>) -> Signal<Value, Error> {
		return Signal { observer in
			let disposable = SerialDisposable()
			
			disposable.inner = trigger.observe { event in
				switch event {
				case .value, .completed:
					disposable.inner = self.observe(observer)
					
				case .failed, .interrupted:
					break
				}
			}
			
			return disposable
		}
	}

	/// Forward events from `self` with history: values of the returned signal
	/// are a tuples whose first member is the previous value and whose second member
	/// is the current value. `initial` is supplied as the first member when `self`
	/// sends its first value.
	///
	/// - parameters:
	///   - initial: A value that will be combined with the first value sent by
	///              `self`.
	///
	/// - returns: A signal that sends tuples that contain previous and current
	///            sent values of `self`.
	public func combinePrevious(_ initial: Value) -> Signal<(Value, Value), Error> {
		return scan((initial, initial)) { previousCombinedValues, newValue in
			return (previousCombinedValues.1, newValue)
		}
	}


	/// Send only the final value and then immediately completes.
	///
	/// - parameters:
	///   - initial: Initial value for the accumulator.
	///   - combine: A closure that accepts accumulator and sent value of
	///              `self`.
	///
	/// - returns: A signal that sends accumulated value after `self` completes.
	public func reduce<U>(_ initial: U, _ combine: @escaping (U, Value) -> U) -> Signal<U, Error> {
		// We need to handle the special case in which `signal` sends no values.
		// We'll do that by sending `initial` on the output signal (before
		// taking the last value).
		let (scannedSignalWithInitialValue, outputSignalObserver) = Signal<U, Error>.pipe()
		let outputSignal = scannedSignalWithInitialValue.take(last: 1)

		// Now that we've got takeLast() listening to the piped signal, send
        // that initial value.
		outputSignalObserver.send(value: initial)

		// Pipe the scanned input signal into the output signal.
		self.scan(initial, combine)
			.observe(outputSignalObserver)

		return outputSignal
	}

	/// Aggregate values into a single combined value. When `self` emits its
	/// first value, `combine` is invoked with `initial` as the first argument
	/// and that emitted value as the second argument. The result is emitted
	/// from the signal returned from `scan`. That result is then passed to
	/// `combine` as the first argument when the next value is emitted, and so
	/// on.
	///
	/// - parameters:
	///   - initial: Initial value for the accumulator.
	///   - combine: A closure that accepts accumulator and sent value of
	///              `self`.
	///
	/// - returns: A signal that sends accumulated value each time `self` emits
	///            own value.
	public func scan<U>(_ initial: U, _ combine: @escaping (U, Value) -> U) -> Signal<U, Error> {
		return Signal { observer in
			var accumulator = initial

			return self.observe { event in
				observer.action(event.map { value in
					accumulator = combine(accumulator, value)
					return accumulator
				})
			}
		}
	}
}

extension SignalProtocol where Value: Equatable {
	/// Forward only those values from `self` which are not duplicates of the
	/// immedately preceding value. 
	///
	/// - note: The first value is always forwarded.
	///
	/// - returns: A signal that does not send two equal values sequentially.
	public func skipRepeats() -> Signal<Value, Error> {
		return skipRepeats(==)
	}
}

extension SignalProtocol {
	/// Forward only those values from `self` which do not pass `isRepeat` with
	/// respect to the previous value. 
	///
	/// - note: The first value is always forwarded.
	///
	/// - parameters:
	///   - isRepeate: A closure that accepts previous and current values of
	///                `self` and returns `Bool` whether these values are
	///                repeating.
	///
	/// - returns: A signal that forwards only those values that fail given
	///            `isRepeat` predicate.
	public func skipRepeats(_ isRepeat: @escaping (Value, Value) -> Bool) -> Signal<Value, Error> {
		return self
			.scan((nil, false)) { (accumulated: (Value?, Bool), next: Value) -> (value: Value?, repeated: Bool) in
				switch accumulated.0 {
				case nil:
					return (next, false)
				case let prev? where isRepeat(prev, next):
					return (prev, true)
				case _?:
					return (Optional(next), false)
				}
			}
			.filter { !$0.repeated }
			.filterMap { $0.value }
	}

	/// Do not forward any values from `self` until `predicate` returns false,
	/// at which point the returned signal behaves exactly like `signal`.
	///
	/// - parameters:
	///   - predicate: A closure that accepts a value and returns whether `self`
	///                should still not forward that value to a `signal`.
	///
	/// - returns: A signal that sends only forwarded values from `self`.
	public func skip(while predicate: @escaping (Value) -> Bool) -> Signal<Value, Error> {
		return Signal { observer in
			var shouldSkip = true

			return self.observe { event in
				switch event {
				case let .value(value):
					shouldSkip = shouldSkip && predicate(value)
					if !shouldSkip {
						fallthrough
					}

				case .failed, .completed, .interrupted:
					observer.action(event)
				}
			}
		}
	}

	/// Forward events from `self` until `replacement` begins sending events.
	///
	/// - parameters:
	///   - replacement: A signal to wait to wait for values from and start
	///                  sending them as a replacement to `self`'s values.
	///
	/// - returns: A signal which passes through `value`, failed, and
	///            `interrupted` events from `self` until `replacement` sends
	///            an event, at which point the returned signal will send that
	///            event and switch to passing through events from `replacement`
	///            instead, regardless of whether `self` has sent events
	///            already.
	public func take(untilReplacement signal: Signal<Value, Error>) -> Signal<Value, Error> {
		return Signal { observer in
			let disposable = CompositeDisposable()

			let signalDisposable = self.observe { event in
				switch event {
				case .completed:
					break

				case .value, .failed, .interrupted:
					observer.action(event)
				}
			}

			disposable += signalDisposable
			disposable += signal.observe { event in
				signalDisposable?.dispose()
				observer.action(event)
			}

			return disposable
		}
	}

	/// Wait until `self` completes and then forward the final `count` values
	/// on the returned signal.
	///
	/// - parameters:
	///   - count: Number of last events to send after `self` completes.
	///
	/// - returns: A signal that receives up to `count` values from `self`
	///            after `self` completes.
	public func take(last count: Int) -> Signal<Value, Error> {
		return Signal { observer in
			var buffer: [Value] = []
			buffer.reserveCapacity(count)

			return self.observe { event in
				switch event {
				case let .value(value):
					// To avoid exceeding the reserved capacity of the buffer, 
					// we remove then add. Remove elements until we have room to 
					// add one more.
					while (buffer.count + 1) > count {
						buffer.remove(at: 0)
					}
					
					buffer.append(value)
				case let .failed(error):
					observer.send(error: error)
				case .completed:
					buffer.forEach(observer.send(value:))
					
					observer.sendCompleted()
				case .interrupted:
					observer.sendInterrupted()
				}
			}
		}
	}

	/// Forward any values from `self` until `predicate` returns false, at which
	/// point the returned signal will complete.
	///
	/// - parameters:
	///   - predicate: A closure that accepts value and returns `Bool` value
	///                whether `self` should forward it to `signal` and continue
	///                sending other events.
	///
	/// - returns: A signal that sends events until the values sent by `self`
	///            pass the given `predicate`.
	public func take(while predicate: @escaping (Value) -> Bool) -> Signal<Value, Error> {
		return Signal { observer in
			return self.observe { event in
				if let value = event.value, !predicate(value) {
					observer.sendCompleted()
				} else {
					observer.action(event)
				}
			}
		}
	}
}

private struct ZipState<Left, Right> {
	var values: (left: [Left], right: [Right]) = ([], [])
	var isCompleted: (left: Bool, right: Bool) = (false, false)

	var isFinished: Bool {
		return (isCompleted.left && values.left.isEmpty) || (isCompleted.right && values.right.isEmpty)
	}
}

extension SignalProtocol {
	/// Zip elements of two signals into pairs. The elements of any Nth pair
	/// are the Nth elements of the two input signals.
	///
	/// - parameters:
	///   - otherSignal: A signal to zip values with.
	///
	/// - returns: A signal that sends tuples of `self` and `otherSignal`.
	public func zip<U>(with other: Signal<U, Error>) -> Signal<(Value, U), Error> {
		return Signal { observer in
			let state = Atomic(ZipState<Value, U>())
			let disposable = CompositeDisposable()
			
			let flush = {
				var tuple: (Value, U)?
				var isFinished = false

				state.modify { state in
					guard !state.values.left.isEmpty && !state.values.right.isEmpty else {
						isFinished = state.isFinished
						return
					}

					tuple = (state.values.left.removeFirst(), state.values.right.removeFirst())
					isFinished = state.isFinished
				}

				if let tuple = tuple {
					observer.send(value: tuple)
				}

				if isFinished {
					observer.sendCompleted()
				}
			}
			
			let onFailed = observer.send(error:)
			let onInterrupted = observer.sendInterrupted

			disposable += self.observe { event in
				switch event {
				case let .value(value):
					state.modify {
						$0.values.left.append(value)
					}
					flush()

				case let .failed(error):
					onFailed(error)

				case .completed:
					state.modify {
						$0.isCompleted.left = true
					}
					flush()

				case .interrupted:
					onInterrupted()
				}
			}

			disposable += other.observe { event in
				switch event {
				case let .value(value):
					state.modify {
						$0.values.right.append(value)
					}
					flush()

				case let .failed(error):
					onFailed(error)

				case .completed:
					state.modify {
						$0.isCompleted.right = true
					}
					flush()

				case .interrupted:
					onInterrupted()
				}
			}
			
			return disposable
		}
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
	///         value will be discarded and the returned signal will terminate
	///         immediately.
	///
	/// - note: If the device time changed backwards before previous date while
	///         a value is being throttled, and if there is a new value sent,
	///         the new value will be passed anyway.
	///
	/// - precondition: `interval` must be non-negative number.
	///
	/// - parameters:
	///   - interval: Number of seconds to wait between sent values.
	///   - scheduler: A scheduler to deliver events on.
	///
	/// - returns: A signal that sends values at least `interval` seconds 
	///            appart on a given scheduler.
	public func throttle(_ interval: TimeInterval, on scheduler: DateScheduler) -> Signal<Value, Error> {
		precondition(interval >= 0)

		return Signal { observer in
			let state: Atomic<ThrottleState<Value>> = Atomic(ThrottleState())
			let schedulerDisposable = SerialDisposable()

			let disposable = CompositeDisposable()
			disposable += schedulerDisposable

			disposable += self.observe { event in
				guard let value = event.value else {
					schedulerDisposable.inner = scheduler.schedule {
						observer.action(event)
					}
					return
				}

				var scheduleDate: Date!
				state.modify {
					$0.pendingValue = value

					let proposedScheduleDate: Date
					if let previousDate = $0.previousDate, previousDate.compare(scheduler.currentDate) != .orderedDescending {
						proposedScheduleDate = previousDate.addingTimeInterval(interval)
					} else {
						proposedScheduleDate = scheduler.currentDate
					}

					switch proposedScheduleDate.compare(scheduler.currentDate) {
					case .orderedAscending:
						scheduleDate = scheduler.currentDate

					case .orderedSame: fallthrough
					case .orderedDescending:
						scheduleDate = proposedScheduleDate
					}
				}

				schedulerDisposable.inner = scheduler.schedule(after: scheduleDate) {
					let pendingValue: Value? = state.modify { state in
						defer {
							if state.pendingValue != nil {
								state.pendingValue = nil
								state.previousDate = scheduleDate
							}
						}
						return state.pendingValue
					}
					
					if let pendingValue = pendingValue {
						observer.send(value: pendingValue)
					}
				}
			}

			return disposable
		}
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
	/// - returns: A signal that sends values only while `shouldThrottle` is false.
	public func throttle<P: PropertyProtocol>(while shouldThrottle: P, on scheduler: Scheduler) -> Signal<Value, Error>
		where P.Value == Bool
	{
		return Signal { observer in
			let initial: ThrottleWhileState<Value> = .resumed
			let state = Atomic(initial)
			let schedulerDisposable = SerialDisposable()

			let disposable = CompositeDisposable()
			disposable += schedulerDisposable

			disposable += shouldThrottle.producer
				.skipRepeats()
				.startWithValues { shouldThrottle in
					let valueToSend = state.modify { state -> Value? in
						guard !state.isTerminated else { return nil }

						if shouldThrottle {
							state = .throttled(nil)
						} else {
							defer { state = .resumed }

							if case let .throttled(value?) = state {
								return value
							}
						}

						return nil
					}

					if let value = valueToSend {
						schedulerDisposable.inner = scheduler.schedule {
							observer.send(value: value)
						}
					}
				}

			disposable += self.observe { event in
				let eventToSend = state.modify { state -> Event<Value, Error>? in
					switch event {
					case let .value(value):
						switch state {
						case .throttled:
							state = .throttled(value)
							return nil
						case .resumed:
							return event
						case .terminated:
							return nil
						}

					case .completed, .interrupted, .failed:
						state = .terminated
						return event
					}
				}

				if let event = eventToSend {
					schedulerDisposable.inner = scheduler.schedule {
						observer.action(event)
					}
				}
			}

			return disposable
		}
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
	/// - note: If the input signal terminates while a value is being debounced, 
	///         that value will be discarded and the returned signal will 
	///         terminate immediately.
	///
	/// - precondition: `interval` must be non-negative number.
	///
	/// - parameters:
	///   - interval: A number of seconds to wait before sending a value.
	///   - scheduler: A scheduler to send values on.
	///
	/// - returns: A signal that sends values that are sent from `self` at least
	///            `interval` seconds apart.
	public func debounce(_ interval: TimeInterval, on scheduler: DateScheduler) -> Signal<Value, Error> {
		precondition(interval >= 0)

		let d = SerialDisposable()
		
		return Signal { observer in
			return self.observe { event in
				switch event {
				case let .value(value):
					let date = scheduler.currentDate.addingTimeInterval(interval)
					d.inner = scheduler.schedule(after: date) {
						observer.send(value: value)
					}

				case .completed, .failed, .interrupted:
					d.inner = scheduler.schedule {
						observer.action(event)
					}
				}
			}
		}
	}
}

extension SignalProtocol {
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
	/// - returns: A signal that sends unique values during its lifetime.
	public func uniqueValues<Identity: Hashable>(_ transform: @escaping (Value) -> Identity) -> Signal<Value, Error> {
		return Signal { observer in
			var seenValues: Set<Identity> = []
			
			return self
				.observe { event in
					switch event {
					case let .value(value):
						let identity = transform(value)
						if !seenValues.contains(identity) {
							seenValues.insert(identity)
							fallthrough
						}
						
					case .failed, .completed, .interrupted:
						observer.action(event)
					}
				}
		}
	}
}

extension SignalProtocol where Value: Hashable {
	/// Forward only those values from `self` that are unique across the set of
	/// all values that have been seen.
	///
	/// - note: This causes the values to be retained to check for uniqueness. 
	///         Providing a function that returns a unique value for each sent 
	///         value can help you reduce the memory footprint.
	///
	/// - returns: A signal that sends unique values during its lifetime.
	public func uniqueValues() -> Signal<Value, Error> {
		return uniqueValues { $0 }
	}
}

private struct ThrottleState<Value> {
	var previousDate: Date? = nil
	var pendingValue: Value? = nil
}

private enum ThrottleWhileState<Value> {
	case resumed
	case throttled(Value?)
	case terminated

	var isTerminated: Bool {
		switch self {
		case .terminated:
			return true
		case .resumed, .throttled:
			return false
		}
	}
}

extension SignalProtocol {
	/// Combines the values of all the given signals, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>) -> Signal<(Value, B), Error> {
		return a.combineLatest(with: b)
	}

	/// Combines the values of all the given signals, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>) -> Signal<(Value, B, C), Error> {
		return combineLatest(a, b)
			.combineLatest(with: c)
			.map(repack)
	}

	/// Combines the values of all the given signals, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>) -> Signal<(Value, B, C, D), Error> {
		return combineLatest(a, b, c)
			.combineLatest(with: d)
			.map(repack)
	}

	/// Combines the values of all the given signals, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D, E>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>) -> Signal<(Value, B, C, D, E), Error> {
		return combineLatest(a, b, c, d)
			.combineLatest(with: e)
			.map(repack)
	}

	/// Combines the values of all the given signals, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D, E, F>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>) -> Signal<(Value, B, C, D, E, F), Error> {
		return combineLatest(a, b, c, d, e)
			.combineLatest(with: f)
			.map(repack)
	}

	/// Combines the values of all the given signals, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D, E, F, G>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>) -> Signal<(Value, B, C, D, E, F, G), Error> {
		return combineLatest(a, b, c, d, e, f)
			.combineLatest(with: g)
			.map(repack)
	}

	/// Combines the values of all the given signals, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D, E, F, G, H>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>, _ h: Signal<H, Error>) -> Signal<(Value, B, C, D, E, F, G, H), Error> {
		return combineLatest(a, b, c, d, e, f, g)
			.combineLatest(with: h)
			.map(repack)
	}

	/// Combines the values of all the given signals, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D, E, F, G, H, I>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>, _ h: Signal<H, Error>, _ i: Signal<I, Error>) -> Signal<(Value, B, C, D, E, F, G, H, I), Error> {
		return combineLatest(a, b, c, d, e, f, g, h)
			.combineLatest(with: i)
			.map(repack)
	}

	/// Combines the values of all the given signals, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D, E, F, G, H, I, J>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>, _ h: Signal<H, Error>, _ i: Signal<I, Error>, _ j: Signal<J, Error>) -> Signal<(Value, B, C, D, E, F, G, H, I, J), Error> {
		return combineLatest(a, b, c, d, e, f, g, h, i)
			.combineLatest(with: j)
			.map(repack)
	}

	/// Combines the values of all the given signals, in the manner described by
	/// `combineLatest(with:)`. No events will be sent if the sequence is empty.
	public static func combineLatest<S: Sequence>(_ signals: S) -> Signal<[Value], Error>
		where S.Iterator.Element == Signal<Value, Error>
	{
		var generator = signals.makeIterator()
		if let first = generator.next() {
			let initial = first.map { [$0] }
			return IteratorSequence(generator).reduce(initial) { signal, next in
				signal.combineLatest(with: next).map { $0.0 + [$0.1] }
			}
		}
		
		return .never
	}

	/// Zips the values of all the given signals, in the manner described by
	/// `zipWith`.
	public static func zip<B>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>) -> Signal<(Value, B), Error> {
		return a.zip(with: b)
	}

	/// Zips the values of all the given signals, in the manner described by
	/// `zipWith`.
	public static func zip<B, C>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>) -> Signal<(Value, B, C), Error> {
		return zip(a, b)
			.zip(with: c)
			.map(repack)
	}

	/// Zips the values of all the given signals, in the manner described by
	/// `zipWith`.
	public static func zip<B, C, D>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>) -> Signal<(Value, B, C, D), Error> {
		return zip(a, b, c)
			.zip(with: d)
			.map(repack)
	}

	/// Zips the values of all the given signals, in the manner described by
	/// `zipWith`.
	public static func zip<B, C, D, E>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>) -> Signal<(Value, B, C, D, E), Error> {
		return zip(a, b, c, d)
			.zip(with: e)
			.map(repack)
	}

	/// Zips the values of all the given signals, in the manner described by
	/// `zipWith`.
	public static func zip<B, C, D, E, F>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>) -> Signal<(Value, B, C, D, E, F), Error> {
		return zip(a, b, c, d, e)
			.zip(with: f)
			.map(repack)
	}

	/// Zips the values of all the given signals, in the manner described by
	/// `zipWith`.
	public static func zip<B, C, D, E, F, G>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>) -> Signal<(Value, B, C, D, E, F, G), Error> {
		return zip(a, b, c, d, e, f)
			.zip(with: g)
			.map(repack)
	}

	/// Zips the values of all the given signals, in the manner described by
	/// `zipWith`.
	public static func zip<B, C, D, E, F, G, H>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>, _ h: Signal<H, Error>) -> Signal<(Value, B, C, D, E, F, G, H), Error> {
		return zip(a, b, c, d, e, f, g)
			.zip(with: h)
			.map(repack)
	}

	/// Zips the values of all the given signals, in the manner described by
	/// `zipWith`.
	public static func zip<B, C, D, E, F, G, H, I>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>, _ h: Signal<H, Error>, _ i: Signal<I, Error>) -> Signal<(Value, B, C, D, E, F, G, H, I), Error> {
		return zip(a, b, c, d, e, f, g, h)
			.zip(with: i)
			.map(repack)
	}

	/// Zips the values of all the given signals, in the manner described by
	/// `zipWith`.
	public static func zip<B, C, D, E, F, G, H, I, J>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>, _ h: Signal<H, Error>, _ i: Signal<I, Error>, _ j: Signal<J, Error>) -> Signal<(Value, B, C, D, E, F, G, H, I, J), Error> {
		return zip(a, b, c, d, e, f, g, h, i)
			.zip(with: j)
			.map(repack)
	}

	/// Zips the values of all the given signals, in the manner described by
	/// `zipWith`. No events will be sent if the sequence is empty.
	public static func zip<S: Sequence>(_ signals: S) -> Signal<[Value], Error>
		where S.Iterator.Element == Signal<Value, Error>
	{
		var generator = signals.makeIterator()
		if let first = generator.next() {
			let initial = first.map { [$0] }
			return IteratorSequence(generator).reduce(initial) { signal, next in
				signal.zip(with: next).map { $0.0 + [$0.1] }
			}
		}
		
		return .never
	}
}

extension SignalProtocol {
	/// Forward events from `self` until `interval`. Then if signal isn't 
	/// completed yet, fails with `error` on `scheduler`.
	///
	/// - note: If the interval is 0, the timeout will be scheduled immediately. 
	///         The signal must complete synchronously (or on a faster
	///         scheduler) to avoid the timeout.
	///
	/// - precondition: `interval` must be non-negative number.
	///
	/// - parameters:
	///   - error: Error to send with failed event if `self` is not completed
	///            when `interval` passes.
	///   - interval: Number of seconds to wait for `self` to complete.
	///   - scheudler: A scheduler to deliver error on.
	///
	/// - returns: A signal that sends events for at most `interval` seconds,
	///            then, if not `completed` - sends `error` with failed event
	///            on `scheduler`.
	public func timeout(after interval: TimeInterval, raising error: Error, on scheduler: DateScheduler) -> Signal<Value, Error> {
		precondition(interval >= 0)

		return Signal { observer in
			let disposable = CompositeDisposable()
			let date = scheduler.currentDate.addingTimeInterval(interval)

			disposable += scheduler.schedule(after: date) {
				observer.send(error: error)
			}

			disposable += self.observe(observer)
			return disposable
		}
	}
}

extension SignalProtocol where Error == NoError {
	/// Promote a signal that does not generate failures into one that can.
	///
	/// - note: This does not actually cause failures to be generated for the
	///         given signal, but makes it easier to combine with other signals
	///         that may fail; for example, with operators like 
	///         `combineLatestWith`, `zipWith`, `flatten`, etc.
	///
	/// - parameters:
	///   - _ An `ErrorType`.
	///
	/// - returns: A signal that has an instantiatable `ErrorType`.
	public func promoteErrors<F: Swift.Error>(_: F.Type) -> Signal<Value, F> {
		return Signal { observer in
			return self.observe { event in
				switch event {
				case let .value(value):
					observer.send(value: value)
				case .failed:
					fatalError("NoError is impossible to construct")
				case .completed:
					observer.sendCompleted()
				case .interrupted:
					observer.sendInterrupted()
				}
			}
		}
	}

	/// Forward events from `self` until `interval`. Then if signal isn't
	/// completed yet, fails with `error` on `scheduler`.
	///
	/// - note: If the interval is 0, the timeout will be scheduled immediately.
	///         The signal must complete synchronously (or on a faster
	///         scheduler) to avoid the timeout.
	///
	/// - parameters:
	///   - interval: Number of seconds to wait for `self` to complete.
	///   - error: Error to send with `failed` event if `self` is not completed
	///            when `interval` passes.
	///   - scheudler: A scheduler to deliver error on.
	///
	/// - returns: A signal that sends events for at most `interval` seconds,
	///            then, if not `completed` - sends `error` with `failed` event
	///            on `scheduler`.
	public func timeout<NewError: Swift.Error>(
		after interval: TimeInterval,
		raising error: NewError,
		on scheduler: DateScheduler
	) -> Signal<Value, NewError> {
		return self
			.promoteErrors(NewError.self)
			.timeout(after: interval, raising: error, on: scheduler)
	}
}

extension SignalProtocol where Value == Bool {
	/// Create a signal that computes a logical NOT in the latest values of `self`.
	///
	/// - returns: A signal that emits the logical NOT results.
	public func negate() -> Signal<Value, Error> {
		return self.map(!)
	}
	
	/// Create a signal that computes a logical AND between the latest values of `self`
	/// and `signal`.
	///
	/// - parameters:
	///   - signal: Signal to be combined with `self`.
	///
	/// - returns: A signal that emits the logical AND results.
	public func and(_ signal: Signal<Value, Error>) -> Signal<Value, Error> {
		return self.combineLatest(with: signal).map { $0 && $1 }
	}
	
	/// Create a signal that computes a logical OR between the latest values of `self`
	/// and `signal`.
	///
	/// - parameters:
	///   - signal: Signal to be combined with `self`.
	///
	/// - returns: A signal that emits the logical OR results.
	public func or(_ signal: Signal<Value, Error>) -> Signal<Value, Error> {
		return self.combineLatest(with: signal).map { $0 || $1 }
	}
}

extension SignalProtocol {
	/// Apply `operation` to values from `self` with `success`ful results
	/// forwarded on the returned signal and `failure`s sent as failed events.
	///
	/// - parameters:
	///   - operation: A closure that accepts a value and returns a `Result`.
	///
	/// - returns: A signal that receives `success`ful `Result` as `value` event
	///            and `failure` as failed event.
	public func attempt(_ operation: @escaping (Value) -> Result<(), Error>) -> Signal<Value, Error> {
		return attemptMap { value in
			return operation(value).map {
				return value
			}
		}
	}

	/// Apply `operation` to values from `self` with `success`ful results mapped
	/// on the returned signal and `failure`s sent as failed events.
	///
	/// - parameters:
	///   - operation: A closure that accepts a value and returns a result of
	///                a mapped value as `success`.
	///
	/// - returns: A signal that sends mapped values from `self` if returned
	///            `Result` is `success`ful, `failed` events otherwise.
	public func attemptMap<U>(_ operation: @escaping (Value) -> Result<U, Error>) -> Signal<U, Error> {
		return Signal { observer in
			self.observe { event in
				switch event {
				case let .value(value):
					operation(value).analysis(
						ifSuccess: observer.send(value:),
						ifFailure: observer.send(error:)
					)
				case let .failed(error):
					observer.send(error: error)
				case .completed:
					observer.sendCompleted()
				case .interrupted:
					observer.sendInterrupted()
				}
			}
		}
	}
}

extension SignalProtocol where Error == NoError {
	/// Apply a failable `operation` to values from `self` with successful
	/// results forwarded on the returned signal and thrown errors sent as
	/// failed events.
	///
	/// - parameters:
	///   - operation: A failable closure that accepts a value.
	///
	/// - returns: A signal that forwards successes as `value` events and thrown
	///            errors as `failed` events.
	public func attempt(_ operation: @escaping (Value) throws -> Void) -> Signal<Value, AnyError> {
		return self
			.promoteErrors(AnyError.self)
			.attempt(operation)
	}

	/// Apply a failable `operation` to values from `self` with successful
	/// results mapped on the returned signal and thrown errors sent as
	/// failed events.
	///
	/// - parameters:
	///   - operation: A failable closure that accepts a value and attempts to
	///                transform it.
	///
	/// - returns: A signal that sends successfully mapped values from `self`, or
	///            thrown errors as `failed` events.
	public func attemptMap<U>(_ operation: @escaping (Value) throws -> U) -> Signal<U, AnyError> {
		return self
			.promoteErrors(AnyError.self)
			.attemptMap(operation)
	}
}

extension SignalProtocol where Error == AnyError {
	/// Apply a failable `operation` to values from `self` with successful
	/// results forwarded on the returned signal and thrown errors sent as
	/// failed events.
	///
	/// - parameters:
	///   - operation: A failable closure that accepts a value.
	///
	/// - returns: A signal that forwards successes as `value` events and thrown
	///            errors as `failed` events.
	public func attempt(_ operation: @escaping (Value) throws -> Void) -> Signal<Value, AnyError> {
		return attemptMap { value in
			try operation(value)
			return value
		}
	}

	/// Apply a failable `operation` to values from `self` with successful
	/// results mapped on the returned signal and thrown errors sent as
	/// failed events.
	///
	/// - parameters:
	///   - operation: A failable closure that accepts a value and attempts to
	///                transform it.
	///
	/// - returns: A signal that sends successfully mapped values from `self`, or
	///            thrown errors as `failed` events.
	public func attemptMap<U>(_ operation: @escaping (Value) throws -> U) -> Signal<U, AnyError> {
		return attemptMap { value in
			ReactiveSwift.materialize {
				try operation(value)
			}
		}
	}
}
