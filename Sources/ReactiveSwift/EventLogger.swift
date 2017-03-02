//
//  EventLogger.swift
//  ReactiveSwift
//
//  Created by Rui Peres on 30/04/2016.
//  Copyright © 2016 GitHub. All rights reserved.
//

import Foundation

/// A namespace for logging event types.
public enum LoggingEvent {
	public enum Signal: String {
		case value, completed, failed, terminated, disposed, interrupted

		public static let allEvents: Set<Signal> = [
			.value, .completed, .failed, .terminated, .disposed, .interrupted,
		]
	}

	public enum SignalProducer: String {
		case starting, started, value, completed, failed, terminated, disposed, interrupted

		public static let allEvents: Set<SignalProducer> = [
			.starting, .started, .value, .completed, .failed, .terminated, .disposed, .interrupted,
		]
	}
}

private func defaultEventLog(identifier: String, event: String, fileName: String, functionName: String, lineNumber: Int) {
	print("[\(identifier)] \(event) fileName: \(fileName), functionName: \(functionName), lineNumber: \(lineNumber)")
}

/// A type that represents an event logging function.
/// Signature is:
///		- identifier 
///		- event
///		- fileName
///		- functionName
///		- lineNumber
public typealias EventLogger = (
	_ identifier: String,
	_ event: String,
	_ fileName: String,
	_ functionName: String,
	_ lineNumber: Int
) -> Void

extension SignalProtocol {
	/// Logs all events that the receiver sends. By default, it will print to 
	/// the standard output.
	///
	/// - parameters:
	///   - identifier: a string to identify the Signal firing events.
	///   - events: Types of events to log.
	///   - fileName: Name of the file containing the code which fired the
	///               event.
	///   - functionName: Function where event was fired.
	///   - lineNumber: Line number where event was fired.
	///   - logger: Logger that logs the events.
	///
	/// - returns: Signal that, when observed, logs the fired events.
	public func logEvents(identifier: String = "", events: Set<LoggingEvent.Signal> = LoggingEvent.Signal.allEvents, fileName: String = #file, functionName: String = #function, lineNumber: Int = #line, logger: @escaping EventLogger = defaultEventLog) -> Signal<Value, Error> {
		func log<T>(_ event: LoggingEvent.Signal) -> ((T) -> Void)? {
			return event.logIfNeeded(events: events) { event in
				logger(identifier, event, fileName, functionName, lineNumber)
			}
		}

		return self.on(
			failed: log(.failed),
			completed: log(.completed),
			interrupted: log(.interrupted),
			terminated: log(.terminated),
			disposed: log(.disposed),
			value: log(.value)
		)
	}
}

extension SignalProducerProtocol {
	/// Logs all events that the receiver sends. By default, it will print to 
	/// the standard output.
	///
	/// - parameters:
	///   - identifier: a string to identify the SignalProducer firing events.
	///   - events: Types of events to log.
	///   - fileName: Name of the file containing the code which fired the
	///               event.
	///   - functionName: Function where event was fired.
	///   - lineNumber: Line number where event was fired.
	///   - logger: Logger that logs the events.
	///
	/// - returns: Signal producer that, when started, logs the fired events.
	public func logEvents(identifier: String = "",
	                      events: Set<LoggingEvent.SignalProducer> = LoggingEvent.SignalProducer.allEvents,
	                      fileName: String = #file,
	                      functionName: String = #function,
	                      lineNumber: Int = #line,
	                      logger: @escaping EventLogger = defaultEventLog
	) -> SignalProducer<Value, Error> {
		func log<T>(_ event: LoggingEvent.SignalProducer) -> ((T) -> Void)? {
			return event.logIfNeeded(events: events) { event in
				logger(identifier, event, fileName, functionName, lineNumber)
			}
		}

		return self.on(
			starting: log(.starting),
			started: log(.started),
			failed: log(.failed),
			completed: log(.completed),
			interrupted: log(.interrupted),
			terminated: log(.terminated),
			disposed: log(.disposed),
			value: log(.value)
		)
	}
}

private protocol LoggingEventProtocol: Hashable, RawRepresentable {}
extension LoggingEvent.Signal: LoggingEventProtocol {}
extension LoggingEvent.SignalProducer: LoggingEventProtocol {}

private extension LoggingEventProtocol {
	func logIfNeeded<T>(events: Set<Self>, logger: @escaping (String) -> Void) -> ((T) -> Void)? {
		guard events.contains(self) else {
			return nil
		}

		return { value in
			if value is Void {
				logger("\(self.rawValue)")
			} else {
				logger("\(self.rawValue) \(value)")
			}
		}
	}
}
