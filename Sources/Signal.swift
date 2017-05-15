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
	private var state: State

	/// Used to ensure that state updates are serialized.
	private let updateLock: Lock

	/// Used to ensure that events are serialized during delivery to observers.
	private let sendLock: Lock

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
		updateLock = Lock.make()
		sendLock = Lock.make()

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
	/// - returns: The generator disposable, or `nil` if it has been disposed
	///            of.
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
	/// - returns: A disposable to detach `observer` from `self`. `nil` if `self` has
	///            terminated.
	@discardableResult
	public func observe(_ observer: Observer) -> Disposable? {
		var token: Bag<Observer>.Token?
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

	/// Represents a signal event.
	///
	/// Signals must conform to the grammar:
	/// `value* (failed | completed | interrupted)?`
	public enum Event {
		/// A value provided by the signal.
		case value(Value)

		/// The signal terminated because of an error. No further events will be
		/// received.
		case failed(Error)

		/// The signal successfully terminated. No further events will be received.
		case completed

		/// Event production on the signal has been interrupted. No further events
		/// will be received.
		///
		/// - important: This event does not signify the successful or failed
		///              completion of the signal.
		case interrupted

		/// Whether this event is a completed event.
		public var isCompleted: Bool {
			switch self {
			case .completed:
				return true

			case .value, .failed, .interrupted:
				return false
			}
		}

		/// Whether this event indicates signal termination (i.e., that no further
		/// events will be received).
		public var isTerminating: Bool {
			switch self {
			case .value:
				return false

			case .failed, .completed, .interrupted:
				return true
			}
		}

		/// Lift the given closure over the event's value.
		///
		/// - important: The closure is called only on `value` type events.
		///
		/// - parameters:
		///   - f: A closure that accepts a value and returns a new value
		///
		/// - returns: An event with function applied to a value in case `self` is a
		///            `value` type of event.
		public func map<U>(_ f: (Value) -> U) -> Signal<U, Error>.Event {
			switch self {
			case let .value(value):
				return .value(f(value))

			case let .failed(error):
				return .failed(error)

			case .completed:
				return .completed

			case .interrupted:
				return .interrupted
			}
		}

		/// Lift the given closure over the event's error.
		///
		/// - important: The closure is called only on failed type event.
		///
		/// - parameters:
		///   - f: A closure that accepts an error object and returns
		///        a new error object
		///
		/// - returns: An event with function applied to an error object in case
		///            `self` is a `.Failed` type of event.
		public func mapError<F>(_ f: (Error) -> F) -> Signal<Value, F>.Event {
			switch self {
			case let .value(value):
				return .value(value)

			case let .failed(error):
				return .failed(f(error))

			case .completed:
				return .completed

			case .interrupted:
				return .interrupted
			}
		}

		/// Unwrap the contained `value` value.
		public var value: Value? {
			if case let .value(value) = self {
				return value
			} else {
				return nil
			}
		}

		/// Unwrap the contained `Error` value.
		public var error: Error? {
			if case let .failed(error) = self {
				return error
			} else {
				return nil
			}
		}
	}

	/// An Observer is a simple wrapper around a function which can receive Events
	/// (typically from a Signal).
	public final class Observer {
		public typealias Action = (Event) -> Void

		/// An action that will be performed upon arrival of the event.
		public let action: Action

		/// An initializer that accepts a closure accepting an event for the
		/// observer.
		///
		/// - parameters:
		///   - action: A closure to lift over received event.
		public init(_ action: @escaping Action) {
			self.action = action
		}

		/// An initializer that accepts closures for different event types.
		///
		/// - parameters:
		///   - value: Optional closure executed when a `value` event is observed.
		///   - failed: Optional closure that accepts an `Error` parameter when a
		///             failed event is observed.
		///   - completed: Optional closure executed when a `completed` event is
		///                observed.
		///   - interruped: Optional closure executed when an `interrupted` event is
		///                 observed.
		public convenience init(
			value: ((Value) -> Void)? = nil,
			failed: ((Error) -> Void)? = nil,
			completed: (() -> Void)? = nil,
			interrupted: (() -> Void)? = nil
			) {
			self.init { event in
				switch event {
				case let .value(v):
					value?(v)

				case let .failed(error):
					failed?(error)

				case .completed:
					completed?()

				case .interrupted:
					interrupted?()
				}
			}
		}

		internal convenience init(mappingInterruptedToCompleted observer: Signal<Value, Error>.Observer) {
			self.init { event in
				switch event {
				case .value, .completed, .failed:
					observer.action(event)
				case .interrupted:
					observer.sendCompleted()
				}
			}
		}

		/// Puts a `value` event into `self`.
		///
		/// - parameters:
		///   - value: A value sent with the `value` event.
		public func send(value: Value) {
			action(.value(value))
		}

		/// Puts a failed event into `self`.
		///
		/// - parameters:
		///   - error: An error object sent with failed event.
		public func send(error: Error) {
			action(.failed(error))
		}

		/// Puts a `completed` event into `self`.
		public func sendCompleted() {
			action(.completed)
		}

		/// Puts an `interrupted` event into `self`.
		public func sendInterrupted() {
			action(.interrupted)
		}
	}

	/// The state of a `Signal`.
	///
	/// `SignalState` is guaranteed to be laid out as a tagged pointer by the Swift
	/// compiler in the support targets of the Swift 3.0.1 ABI.
	///
	/// The Swift compiler has also an optimization for enums with payloads that are
	/// all reference counted, and at most one no-payload case.
	private enum State {
		/// The `Signal` is alive.
		case alive(AliveState)

		/// The `Signal` has received a termination event, and is about to be
		/// terminated.
		case terminating(TerminatingState)

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
	private final class AliveState {
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
	private final class TerminatingState {
		/// The observers of the `Signal`.
		fileprivate let observers: Bag<Signal<Value, Error>.Observer>

		///  The termination event.
		fileprivate let event: Event

		/// Create a terminating state.
		///
		/// - parameters:
		///   - observers: The latest bag of observers.
		///   - event: The termination event.
		init(observers: Bag<Signal<Value, Error>.Observer>, event: Event) {
			self.observers = observers
			self.event = event
		}
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
}

extension Signal: SignalProtocol {
	public var signal: Signal {
		return self
	}
}


extension Signal.Event where Value: Equatable, Error: Equatable {
	public static func == (lhs: Signal<Value, Error>.Event, rhs: Signal<Value, Error>.Event) -> Bool {
		switch (lhs, rhs) {
		case let (.value(left), .value(right)):
			return left == right

		case let (.failed(left), .failed(right)):
			return left == right

		case (.completed, .completed):
			return true

		case (.interrupted, .interrupted):
			return true

		default:
			return false
		}
	}
}

extension Signal.Event: CustomStringConvertible {
	public var description: String {
		switch self {
		case let .value(value):
			return "VALUE \(value)"

		case let .failed(error):
			return "FAILED \(error)"

		case .completed:
			return "COMPLETED"

		case .interrupted:
			return "INTERRUPTED"
		}
	}
}

/// Event protocol for constraining signal extensions
public protocol EventProtocol {
	/// The value type of an event.
	associatedtype Value
	/// The error type of an event. If errors aren't possible then `NoError` can
	/// be used.
	associatedtype Error: Swift.Error
	/// Extracts the event from the receiver.
	var event: Signal<Value, Error>.Event { get }
}

extension Signal.Event: EventProtocol {
	public var event: Signal<Value, Error>.Event {
		return self
	}
}

extension Signal {
	/// Observe `self` for all events being emitted.
	///
	/// - note: If `self` has terminated, the closure would be invoked with an
	///         `interrupted` event immediately.
	///
	/// - parameters:
	///   - action: A closure to be invoked with every event from `self`.
	///
	/// - returns: A disposable to detach `action` from `self`. `nil` if `self` has
	///            terminated.
	@discardableResult
	public func observe(_ action: @escaping Signal<Value, Error>.Observer.Action) -> Disposable? {
		return observe(Observer(action))
	}

	/// Observe `self` for all values being emitted, and if any, the failure.
	///
	/// - parameters:
	///   - action: A closure to be invoked with values from `self`, or the propagated
	///             error should any `failed` event is emitted.
	///
	/// - returns: A disposable to detach `action` from `self`. `nil` if `self` has
	///            terminated.
	@discardableResult
	public func observeResult(_ action: @escaping (Result<Value, Error>) -> Void) -> Disposable? {
		return observe(
			Observer(
				value: { action(.success($0)) },
				failed: { action(.failure($0)) }
			)
		)
	}

	/// Observe `self` for its completion.
	///
	/// - parameters:
	///   - action: A closure to be invoked when a `completed` event is emitted.
	///
	/// - returns: A disposable to detach `action` from `self`. `nil` if `self` has
	///            terminated.
	@discardableResult
	public func observeCompleted(_ action: @escaping () -> Void) -> Disposable? {
		return observe(Observer(completed: action))
	}

	/// Observe `self` for its failure.
	///
	/// - parameters:
	///   - action: A closure to be invoked with the propagated error, should any
	///             `failed` event is emitted.
	///
	/// - returns: A disposable to detach `action` from `self`. `nil` if `self` has
	///            terminated.
	@discardableResult
	public func observeFailed(_ action: @escaping (Error) -> Void) -> Disposable? {
		return observe(Observer(failed: action))
	}

	/// Observe `self` for its interruption.
	///
	/// - note: If `self` has terminated, the closure would be invoked immediately.
	///
	/// - parameters:
	///   - action: A closure to be invoked when an `interrupted` event is emitted.
	///
	/// - returns: A disposable to detach `action` from `self`. `nil` if `self` has
	///            terminated.
	@discardableResult
	public func observeInterrupted(_ action: @escaping () -> Void) -> Disposable? {
		return observe(Observer(interrupted: action))
	}
}

extension Signal where Error == NoError {
	/// Observe `self` for all values being emitted.
	///
	/// - parameters:
	///   - action: A closure to be invoked with values from `self`.
	///
	/// - returns: A disposable to detach `action` from `self`. `nil` if `self` has
	///            terminated.
	@discardableResult
	public func observeValues(_ action: @escaping (Value) -> Void) -> Disposable? {
		return observe(Observer(value: action))
	}
}
