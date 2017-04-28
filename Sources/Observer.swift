//
//  Observer.swift
//  ReactiveSwift
//
//  Created by Andy Matuschak on 10/2/15.
//  Copyright © 2015 GitHub. All rights reserved.
//

/// An Observer is a simple wrapper around a function which can receive Events
/// (typically from a Signal).
public struct Observer<Value, Error: Swift.Error> {
	public typealias Action = (Event<Value, Error>) -> Void

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
	public init(
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
