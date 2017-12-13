import Result
import Foundation

extension Signal {
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

extension Signal.Event {
	/// Event Transformation
	///
	/// Given an output sink and a upstream lifetime, an event transformation
	/// yields an input sink which, for every event received, evaluates certain
	/// side effects that emits zero or more events to the given output sink.
	///
	/// Operators are obliged to maintain:
	///
	/// 1. Serial event order
	///    The outcome need not be synchronously emitted, but every event must
	///    be delivered exclusively in serial order.
	///
	/// 2. No side effect upon interruption.
	///    The operator must not perform any side effect upon receving `interrupted`.
	///
	/// When implementing operators with event transformations, one must
	/// acknowledge that the output sink is not necessarily synchronized.
	internal typealias Transformation<U, E: Swift.Error> = (_ outputSink: @escaping Signal<U, E>.Observer.Action, _ upstream: Lifetime) -> Signal<Value, Error>.Observer.Action

	// Examples of ineligible operators (for now):
	//
	// 1. `timeout`
	//    This operator forwards the `failed` event on a different scheduler.
	//
	// 2. `combineLatest`
	//    This operator applies to two or more streams.
	//
	// 3. `SignalProducer.then`
	//    This operator starts a second stream when the first stream completes.
	//
	// 4. `on`
	//    This operator performs side effect upon interruption.
}

extension Signal.Event {
	internal static func filter(_ isIncluded: @escaping (Value) -> Bool) -> Transformation<Value, Error> {
		return { action, _ in
			return { event in
				switch event {
				case let .value(value):
					if isIncluded(value) {
						action(.value(value))
					}

				case .completed:
					action(.completed)

				case let .failed(error):
					action(.failed(error))

				case .interrupted:
					action(.interrupted)
				}
			}
		}
	}

	internal static func filterMap<U>(_ transform: @escaping (Value) -> U?) -> Transformation<U, Error> {
		return { action, _ in
			return { event in
				switch event {
				case let .value(value):
					if let newValue = transform(value) {
						action(.value(newValue))
					}

				case .completed:
					action(.completed)

				case let .failed(error):
					action(.failed(error))

				case .interrupted:
					action(.interrupted)
				}
			}
		}
	}

	internal static func map<U>(_ transform: @escaping (Value) -> U) -> Transformation<U, Error> {
		return { action, _ in
			return { event in
				switch event {
				case let .value(value):
					action(.value(transform(value)))

				case .completed:
					action(.completed)

				case let .failed(error):
					action(.failed(error))

				case .interrupted:
					action(.interrupted)
				}
			}
		}
	}

	internal static func mapError<E>(_ transform: @escaping (Error) -> E) -> Transformation<Value, E> {
		return { action, _ in
			return { event in
				switch event {
				case let .value(value):
					action(.value(value))

				case .completed:
					action(.completed)

				case let .failed(error):
					action(.failed(transform(error)))

				case .interrupted:
					action(.interrupted)
				}
			}
		}
	}

	internal static var materialize: Transformation<Signal<Value, Error>.Event, NoError> {
		return { action, _ in
			return { event in
				action(.value(event))

				switch event {
				case .interrupted:
					action(.interrupted)

				case .completed, .failed:
					action(.completed)

				case .value:
					break
				}
			}
		}
	}

	internal static func attemptMap<U>(_ transform: @escaping (Value) -> Result<U, Error>) -> Transformation<U, Error> {
		return { action, _ in
			return { event in
				switch event {
				case let .value(value):
					switch transform(value) {
					case let .success(value):
						action(.value(value))
					case let .failure(error):
						action(.failed(error))
					}
				case let .failed(error):
					action(.failed(error))
				case .completed:
					action(.completed)
				case .interrupted:
					action(.interrupted)
				}
			}
		}
	}

	internal static func attempt(_ action: @escaping (Value) -> Result<(), Error>) -> Transformation<Value, Error> {
		return attemptMap { value -> Result<Value, Error> in
			return action(value).map { _ in value }
		}
	}
}

extension Signal.Event where Error == AnyError {
	internal static func attempt(_ action: @escaping (Value) throws -> Void) -> Transformation<Value, AnyError> {
		return attemptMap { value in
			try action(value)
			return value
		}
	}

	internal static func attemptMap<U>(_ transform: @escaping (Value) throws -> U) -> Transformation<U, AnyError> {
		return attemptMap { value in
			ReactiveSwift.materialize { try transform(value) }
		}
	}
}

extension Signal.Event {
	internal static func take(first count: Int) -> Transformation<Value, Error> {
		assert(count >= 1)

		return { action, _ in
			var taken = 0

			return { event in
				guard let value = event.value else {
					action(event)
					return
				}

				if taken < count {
					taken += 1
					action(.value(value))
				}

				if taken == count {
					action(.completed)
				}
			}
		}
	}

	internal static func take(last count: Int) -> Transformation<Value, Error> {
		return { action, _ in
			var buffer: [Value] = []
			buffer.reserveCapacity(count)

			return { event in
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
					action(.failed(error))
				case .completed:
					buffer.forEach { action(.value($0)) }
					action(.completed)
				case .interrupted:
					action(.interrupted)
				}
			}
		}
	}

	internal static func take(while shouldContinue: @escaping (Value) -> Bool) -> Transformation<Value, Error> {
		return { action, _ in
			return { event in
				if let value = event.value, !shouldContinue(value) {
					action(.completed)
				} else {
					action(event)
				}
			}
		}
	}

	internal static func skip(first count: Int) -> Transformation<Value, Error> {
		precondition(count > 0)

		return { action, _ in
			var skipped = 0

			return { event in
				if case .value = event, skipped < count {
					skipped += 1
				} else {
					action(event)
				}
			}
		}
	}

	internal static func skip(while shouldContinue: @escaping (Value) -> Bool) -> Transformation<Value, Error> {
		return { action, _ in
			var isSkipping = true

			return { event in
				switch event {
				case let .value(value):
					isSkipping = isSkipping && shouldContinue(value)
					if !isSkipping {
						fallthrough
					}

				case .failed, .completed, .interrupted:
					action(event)
				}
			}
		}
	}
}

extension Signal.Event where Value: EventProtocol {
	internal static var dematerialize: Transformation<Value.Value, Value.Error> {
		return { action, _ in
			return { event in
				switch event {
				case let .value(innerEvent):
					action(innerEvent.event)

				case .failed:
					fatalError("NoError is impossible to construct")

				case .completed:
					action(.completed)

				case .interrupted:
					action(.interrupted)
				}
			}
		}
	}
}

extension Signal.Event where Value: OptionalProtocol {
	internal static var skipNil: Transformation<Value.Wrapped, Error> {
		return filterMap { $0.optional }
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

extension Signal.Event {
	internal static var collect: Transformation<[Value], Error> {
		return collect { _, _ in false }
	}

	internal static func collect(count: Int) -> Transformation<[Value], Error> {
		precondition(count > 0)
		return collect { values in values.count == count }
	}

	internal static func collect(_ shouldEmit: @escaping (_ collectedValues: [Value]) -> Bool) -> Transformation<[Value], Error> {
		return { action, _ in
			let state = CollectState<Value>()

			return { event in
				switch event {
				case let .value(value):
					state.append(value)
					if shouldEmit(state.values) {
						action(.value(state.values))
						state.flush()
					}
				case .completed:
					if !state.isEmpty {
						action(.value(state.values))
					}
					action(.completed)
				case let .failed(error):
					action(.failed(error))
				case .interrupted:
					action(.interrupted)
				}
			}
		}
	}

	internal static func collect(_ shouldEmit: @escaping (_ collected: [Value], _ latest: Value) -> Bool) -> Transformation<[Value], Error> {
		return { action, _ in
			let state = CollectState<Value>()

			return { event in
				switch event {
				case let .value(value):
					if shouldEmit(state.values, value) {
						action(.value(state.values))
						state.flush()
					}
					state.append(value)
				case .completed:
					if !state.isEmpty {
						action(.value(state.values))
					}
					action(.completed)
				case let .failed(error):
					action(.failed(error))
				case .interrupted:
					action(.interrupted)
				}
			}
		}
	}

	/// Implementation detail of `combinePrevious`. A default argument of a `nil` initial
	/// is deliberately avoided, since in the case of `Value` being an optional, the
	/// `nil` literal would be materialized as `Optional<Value>.none` instead of `Value`,
	/// thus changing the semantic.
	internal static func combinePrevious(initial: Value?) -> Transformation<(Value, Value), Error> {
		return { action, _ in
			var previous = initial

			return { event in
				switch event {
				case let .value(value):
					if let previous = previous {
						action(.value((previous, value)))
					}
					previous = value
				case .completed:
					action(.completed)
				case let .failed(error):
					action(.failed(error))
				case .interrupted:
					action(.interrupted)
				}
			}
		}
	}

	internal static func skipRepeats(_ isEquivalent: @escaping (Value, Value) -> Bool) -> Transformation<Value, Error> {
		return { action, _ in
			var previous: Value?

			return { event in
				switch event {
				case let .value(value):
					if let previous = previous, isEquivalent(previous, value) {
						return
					}
					previous = value
					fallthrough
				case .completed, .interrupted, .failed:
					action(event)
				}
			}
		}
	}

	internal static func uniqueValues<Identity: Hashable>(_ transform: @escaping (Value) -> Identity) -> Transformation<Value, Error> {
		return { action, _ in
			var seenValues: Set<Identity> = []

			return { event in
				switch event {
				case let .value(value):
					let identity = transform(value)
					let (inserted, _) = seenValues.insert(identity)
					if inserted {
						fallthrough
					}

				case .failed, .completed, .interrupted:
					action(event)
				}
			}
		}
	}

	internal static func scan<U>(into initialResult: U, _ nextPartialResult: @escaping (inout U, Value) -> Void) -> Transformation<U, Error> {
		return { action, _ in
			var accumulator = initialResult

			return { event in
				action(event.map { value in
					nextPartialResult(&accumulator, value)
					return accumulator
				})
			}
		}
	}

	internal static func scan<U>(_ initialResult: U, _ nextPartialResult: @escaping (U, Value) -> U) -> Transformation<U, Error> {
		return scan(into: initialResult) { $0 = nextPartialResult($0, $1) }
	}

	internal static func reduce<U>(into initialResult: U, _ nextPartialResult: @escaping (inout U, Value) -> Void) -> Transformation<U, Error> {
		return { action, _ in
			var accumulator = initialResult

			return { event in
				switch event {
				case let .value(value):
					nextPartialResult(&accumulator, value)
				case .completed:
					action(.value(accumulator))
					action(.completed)
				case .interrupted:
					action(.interrupted)
				case let .failed(error):
					action(.failed(error))
				}
			}
		}
	}

	internal static func reduce<U>(_ initialResult: U, _ nextPartialResult: @escaping (U, Value) -> U) -> Transformation<U, Error> {
		return reduce(into: initialResult) { $0 = nextPartialResult($0, $1) }
	}

	internal static func observe(on scheduler: Scheduler) -> Transformation<Value, Error> {
		return { action, _ in
			return { event in
				scheduler.schedule {
					action(event)
				}
			}
		}
	}

	internal static func delay(_ interval: TimeInterval, on scheduler: DateScheduler) -> Transformation<Value, Error> {
		precondition(interval >= 0)

		return { action, _ in
			return { event in
				switch event {
				case .failed, .interrupted:
					scheduler.schedule {
						action(event)
					}

				case .value, .completed:
					let date = scheduler.currentDate.addingTimeInterval(interval)
					scheduler.schedule(after: date) {
						action(event)
					}
				}
			}
		}
	}

	internal static func throttle(_ interval: TimeInterval, on scheduler: DateScheduler) -> Transformation<Value, Error> {
		precondition(interval >= 0)

		return { action, _ in
			let state: Atomic<ThrottleState<Value>> = Atomic(ThrottleState())
			let schedulerDisposable = SerialDisposable()

			return { event in
				guard let value = event.value else {
					schedulerDisposable.inner = scheduler.schedule {
						action(event)
					}
					return
				}

				let scheduleDate: Date = state.modify { state in
					state.pendingValue = value

					let proposedScheduleDate: Date
					if let previousDate = state.previousDate, previousDate.compare(scheduler.currentDate) != .orderedDescending {
						proposedScheduleDate = previousDate.addingTimeInterval(interval)
					} else {
						proposedScheduleDate = scheduler.currentDate
					}

					switch proposedScheduleDate.compare(scheduler.currentDate) {
					case .orderedAscending:
						return scheduler.currentDate

					case .orderedSame: fallthrough
					case .orderedDescending:
						return proposedScheduleDate
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
						action(.value(pendingValue))
					}
				}
			}
		}
	}

	internal static func debounce(_ interval: TimeInterval, on scheduler: DateScheduler) -> Transformation<Value, Error> {
		precondition(interval >= 0)

		return { action, _ in
			let d = SerialDisposable()

			return { event in
				switch event {
				case let .value(value):
					let date = scheduler.currentDate.addingTimeInterval(interval)
					d.inner = scheduler.schedule(after: date) {
						action(.value(value))
					}

				case .completed, .failed, .interrupted:
					d.inner = scheduler.schedule {
						action(event)
					}
				}
			}
		}
	}
}

private struct ThrottleState<Value> {
	var previousDate: Date?
	var pendingValue: Value?
}

extension Signal.Event where Error == NoError {
	internal static func promoteError<F>(_: F.Type) -> Transformation<Value, F> {
		return { action, _ in
			return { event in
				switch event {
				case let .value(value):
					action(.value(value))
				case .failed:
					fatalError("NoError is impossible to construct")
				case .completed:
					action(.completed)
				case .interrupted:
					action(.interrupted)
				}
			}
		}
	}
}

extension Signal.Event where Value == Never {
	internal static func promoteValue<U>(_: U.Type) -> Transformation<U, Error> {
		return { action, _ in
			return { event in
				switch event {
				case .value:
					fatalError("Never is impossible to construct")
				case let .failed(error):
					action(.failed(error))
				case .completed:
					action(.completed)
				case .interrupted:
					action(.interrupted)
				}
			}
		}
	}
}

extension Signal.Event {
	internal static func take(during lifetime: Lifetime) -> Transformation<Value, Error> {
		return { action, innerLifetime in
			innerLifetime += lifetime.observeEnded {
				action(.completed)
			}

			return action
		}
	}

	internal static func take<S: EventStream>(until stream: S) -> Transformation<Value, Error> where S.Value == (), S.Error == NoError {
		return { action, lifetime in
			stream.subscribe { interrupter in
				lifetime += interrupter

				return Signal<(), NoError>.Observer { event in
					switch event {
					case .value, .completed:
						action(.completed)
					case .failed, .interrupted:
						break
					}
				}
			}

			return action
		}
	}
}

private enum TerminationState: Int32 {
	case idle
	case terminated
	case blocked
}

extension Signal.Event {
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

	internal static func makeSynchronizing(_ action: @escaping Signal.Observer.Action, disposable: Disposable? = nil) -> Signal.Observer.Action {
		let sendLock = Lock.make()
		let termination = UnsafeAtomicState(TerminationState.idle)
		let deallocator = ScopedDisposable(AnyDisposable(termination.deinitialize))

		// No one loves IUO, but logically speaking it is always available when
		// termination state is `blocked`.
		//
		// This variable is only write once and subsequently read once.
		var terminalEvent: Signal.Event!

		return { [deallocator] event in
			// All `sendLock` holders for delivering values must invoke
			// `tryToCommitTermination` after releasing the lock. This ensures
			// the terminal event would eventually be picked up.
			@inline(__always)
			func tryToCommitTermination() {
				if termination.is(.blocked) && sendLock.try() {
					// The transition CAS here acts as an acquire fence for
					// `terminalEvent`.
					let shouldTerminate = termination.tryTransition(from: .blocked, to: .terminated)

					if shouldTerminate {
						action(terminalEvent)
						_ = deallocator
					}

					sendLock.unlock()

					if shouldTerminate {
						disposable?.dispose()
					}
				}
			}

			if case .value = event {
				sendLock.lock()
				action(event)
				sendLock.unlock()

				tryToCommitTermination()
			} else {
				// If the signal is terminating, we can gracefully ignore any
				// other attempt.
				if termination.tryTransition(from: .idle, to: .terminated) {
					guard !sendLock.try() else {
						action(event)
						sendLock.unlock()
						disposable?.dispose()
						return
					}

					terminalEvent = event

					// The transition CAS here acts as a release fence for
					// `terminalEvent`.
					let succeeds = termination.tryTransition(from: .terminated, to: .blocked)
					assert(succeeds)

					tryToCommitTermination()
				}
			}
		}
	}
}
