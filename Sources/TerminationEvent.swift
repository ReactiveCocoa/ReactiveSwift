import Foundation
import Dispatch

extension Signal {
	/// Represents a signal termination.
	///
	/// Signals must conform to the grammar:
	/// `value* (failed | completed | interrupted)?`
	///
	/// seealso: `Signal.Event`.
	public enum Termination {
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

			case .failed, .interrupted:
				return false
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
		public func mapError<F>(_ f: (Error) -> F) -> Signal<Value, F>.Termination {
			switch self {
			case let .failed(error):
				return .failed(f(error))

			case .completed:
				return .completed

			case .interrupted:
				return .interrupted
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

		public init?(_ event: Event) {
			switch event {
			case let .failed(error):
				self = .failed(error)

			case .completed:
				self = .completed

			case .interrupted:
				self = .interrupted

			case .value:
				return nil
			}
		}
	}
}

extension Signal.Termination: Equatable where Error: Equatable {}

extension Signal.Termination: CustomStringConvertible {
	public var description: String {
		switch self {
		case let .failed(error):
			return "FAILED \(error)"

		case .completed:
			return "COMPLETED"

		case .interrupted:
			return "INTERRUPTED"
		}
	}
}
