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
		private let _send: Action

		/// An action that will be performed upon arrival of the event.
		@available(*, deprecated: 2.0, renamed:"send(_:)")
		public var action: Action {
			guard !interruptsOnDeinit && wrapped == nil else {
				return { self._send($0) }
			}
			return _send
		}

		/// Whether the observer should send an `interrupted` event as it deinitializes.
		private let interruptsOnDeinit: Bool

		/// The target observer of `self`.
		private let wrapped: AnyObject?

		/// An initializer that transforms the action of the given observer with the
		/// given transform.
		///
		/// If the given observer would perform side effect on deinitialization, the
		/// created observer would retain it.
		///
		/// - parameters:
		///   - observer: The observer to transform.
		///   - transform: The transform.
		///   - disposable: The disposable to be disposed of when the `TransformerCore`
		///                 yields any terminal event. If `observer` is a `Signal` input
		///                 observer, this can be omitted.
		internal init<U, E>(
			_ observer: Signal<U, E>.Observer,
			_ transform: @escaping Event.Transformation<U, E>,
			_ disposable: Disposable? = nil
		) {
			var hasDeliveredTerminalEvent = false

			self._send = transform { event in
				if !hasDeliveredTerminalEvent {
					observer._send(event)

					if event.isTerminating {
						hasDeliveredTerminalEvent = true
						disposable?.dispose()
					}
				}
			}

			self.wrapped = observer.interruptsOnDeinit ? observer : nil
			self.interruptsOnDeinit = false
		}

		/// An initializer that accepts a closure accepting an event for the
		/// observer.
		///
		/// - parameters:
		///   - action: A closure to lift over received event.
		///   - interruptsOnDeinit: `true` if the observer should send an `interrupted`
		///                         event as it deinitializes. `false` otherwise.
		internal init(action: @escaping Action, interruptsOnDeinit: Bool) {
			self._send = action
			self.wrapped = nil
			self.interruptsOnDeinit = interruptsOnDeinit
		}

		/// An initializer that accepts a closure accepting an event for the 
		/// observer.
		///
		/// - parameters:
		///   - action: A closure to lift over received event.
		public init(_ action: @escaping Action) {
			self._send = action
			self.wrapped = nil
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
					observer.send(event)
				case .interrupted:
					observer.sendCompleted()
				}
			}
		}

		deinit {
			if interruptsOnDeinit {
				// Since `Signal` would ensure that only one terminal event would ever be
				// sent for any given `Signal`, we do not need to assert any condition
				// here.
				_send(.interrupted)
			}
		}

		/// Puts an event into `self`.
		public func send(_ event: Event) {
			_send(event)
		}

		/// Puts a `value` event into `self`.
		///
		/// - parameters:
		///   - value: A value sent with the `value` event.
		public func send(value: Value) {
			_send(.value(value))
		}

		/// Puts a failed event into `self`.
		///
		/// - parameters:
		///   - error: An error object sent with failed event.
		public func send(error: Error) {
			_send(.failed(error))
		}

		/// Puts a `completed` event into `self`.
		public func sendCompleted() {
			_send(.completed)
		}

		/// Puts an `interrupted` event into `self`.
		public func sendInterrupted() {
			_send(.interrupted)
		}
	}
}
