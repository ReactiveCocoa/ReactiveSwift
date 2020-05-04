//
//  Observer.swift
//  ReactiveSwift
//
//  Created by Andy Matuschak on 10/2/15.
//  Copyright © 2015 GitHub. All rights reserved.
//

extension Signal {
	/// An Observer is a simple wrapper around a function which can receive Events
	/// (typically from a Signal).
	public final class Observer {
		public typealias Action = (Event) -> Void

		private let valueSink: (Value) -> Void
		private let terminationSink: (Termination) -> Void

		/// Whether the observer should send an `interrupted` event as it deinitializes.
		private let interruptsOnDeinit: Bool

		/// An initializer that accepts a closure accepting an event for the
		/// observer.
		///
		/// - parameters:
		///   - action: A closure to lift over received event.
		///   - interruptsOnDeinit: `true` if the observer should send an `interrupted`
		///                         event as it deinitializes. `false` otherwise.
		internal init(value: @escaping (Value) -> Void, termination: @escaping (Termination) -> Void, interruptsOnDeinit: Bool) {
			self.valueSink = value
			self.terminationSink = termination
			self.interruptsOnDeinit = interruptsOnDeinit
		}

		/// An initializer that accepts a closure accepting an event for the
		/// observer.
		///
		/// - parameters:
		///   - action: A closure to lift over received event.
		public init(value: @escaping (Value) -> Void, termination: @escaping (Termination) -> Void) {
			self.valueSink = value
			self.terminationSink = termination
			self.interruptsOnDeinit = false
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
			self.init(
				value: { value?($0) },
				termination: { termination in
					switch termination {
					case .completed:
						completed?()
					case .interrupted:
						interrupted?()
					case let .failed(error):
						failed?(error)
					}
				}
			)
		}

		internal convenience init(mappingInterruptedToCompleted observer: Signal<Value, Error>.Observer) {
			self.init(
				value: observer.valueSink,
				termination: { [sink = observer.terminationSink] termination in
					switch termination {
					case .completed, .failed:
						sink(termination)
					case .interrupted:
						sink(.completed)
					}
				}
			)
		}

		deinit {
			if interruptsOnDeinit {
				// Since `Signal` would ensure that only one terminal event would ever be
				// sent for any given `Signal`, we do not need to assert any condition
				// here.
				terminationSink(.interrupted)
			}
		}

		/// Puts an event into `self`.
		public func send(_ event: Event) {
			switch event {
			case let .value(value):
				valueSink(value)
			case .completed:
				terminationSink(.completed)
			case .interrupted:
				terminationSink(.interrupted)
			case let .failed(error):
				terminationSink(.failed(error))
			}
		}

		/// Puts a `value` event into `self`.
		///
		/// - parameters:
		///   - value: A value sent with the `value` event.
		public func send(value: Value) {
			valueSink(value)
		}

		/// Puts a failed event into `self`.
		///
		/// - parameters:
		///   - error: An error object sent with failed event.
		public func send(error: Error) {
			terminationSink(.failed(error))
		}

		/// Puts a `completed` event into `self`.
		public func sendCompleted() {
			terminationSink(.completed)
		}

		/// Puts an `interrupted` event into `self`.
		public func sendInterrupted() {
			terminationSink(.interrupted)
		}
	}
}

/// FIXME: Cannot be placed in `Deprecations+Removal.swift` if compiling with
///        Xcode 9.2.
extension Signal.Observer {
	/// An action that will be performed upon arrival of the event.
	@available(*, unavailable, renamed:"send(_:)")
	public var action: Action { fatalError() }
}
