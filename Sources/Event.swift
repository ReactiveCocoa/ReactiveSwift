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
	internal typealias Transformation<U, E: Swift.Error> = (@escaping Signal<U, E>.Observer.Action) -> (Signal<Value, Error>.Event) -> Void

	internal static func filter(_ isIncluded: @escaping (Value) -> Bool) -> Transformation<Value, Error> {
		return { action in
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
		return { action in
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
		return { action in
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
		return { action in
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
		return { action in
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

	internal static func take(first count: Int) -> Transformation<Value, Error> {
		assert(count >= 1)

		return { action in
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

	internal static func skip(first count: Int) -> Transformation<Value, Error> {
		precondition(count > 0)

		return { action in
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
}

extension Signal.Event where Value: EventProtocol {
	internal static var dematerialize: Transformation<Value.Value, Value.Error> {
		return { action in
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
		return { action in
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
		return { action in
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

	internal static func observe(on scheduler: Scheduler) -> Transformation<Value, Error> {
		return { action in
			return { event in
				scheduler.schedule {
					action(event)
				}
			}
		}
	}

	internal static func delay(_ interval: TimeInterval, on scheduler: DateScheduler) -> Transformation<Value, Error> {
		precondition(interval >= 0)

		return { action in
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
}
