//
//  FoundationExtensions.swift
//  ReactiveSwift
//
//  Created by Justin Spahr-Summers on 2014-10-19.
//  Copyright (c) 2014 GitHub. All rights reserved.
//

import Foundation
import Dispatch
import enum Result.NoError
import struct Result.AnyError

#if os(Linux)
	import let CDispatch.NSEC_PER_USEC
	import let CDispatch.NSEC_PER_SEC
#endif

extension NotificationCenter: ReactiveExtensionsProvider {}

extension Reactive where Base: NotificationCenter {
	/// Returns a Signal to observe posting of the specified notification.
	///
	/// - parameters:
	///   - name: name of the notification to observe
	///   - object: an instance which sends the notifications
	///
	/// - returns: A Signal of notifications posted that match the given criteria.
	///
	/// - note: The signal does not terminate naturally. Observers must be
	///         explicitly disposed to avoid leaks.
	public func notifications(forName name: Notification.Name?, object: AnyObject? = nil) -> Signal<Notification, NoError> {
		return Signal { [base = self.base] observer in
			let notificationObserver = base.addObserver(forName: name, object: object, queue: nil) { notification in
				observer.send(value: notification)
			}

			return AnyDisposable {
				base.removeObserver(notificationObserver)
			}
		}
	}
}

private let defaultSessionError = NSError(domain: "org.reactivecocoa.ReactiveSwift.Reactivity.URLSession.dataWithRequest",
                                          code: 1,
                                          userInfo: nil)

extension URLSession: ReactiveExtensionsProvider {}

extension Reactive where Base: URLSession {
	/// Returns a SignalProducer which performs the work associated with an
	/// `NSURLSession`
	///
	/// - parameters:
	///   - request: A request that will be performed when the producer is
	///              started
	///
	/// - returns: A producer that will execute the given request once for each
	///            invocation of `start()`.
	///
	/// - note: This method will not send an error event in the case of a server
	///         side error (i.e. when a response with status code other than
	///         200...299 is received).
	public func data(with request: URLRequest) -> SignalProducer<(Data, URLResponse), AnyError> {
		return SignalProducer { [base = self.base] observer, lifetime in
			let task = base.dataTask(with: request) { data, response, error in
				if let data = data, let response = response {
					observer.send(value: (data, response))
					observer.sendCompleted()
				} else {
					observer.send(error: AnyError(error ?? defaultSessionError))
				}
			}

			lifetime.observeEnded(task.cancel)
			task.resume()
		}
	}
}

extension Date {
	internal func addingTimeInterval(_ interval: DispatchTimeInterval) -> Date {
		return addingTimeInterval(interval.timeInterval)
	}
}

extension DispatchTimeInterval {
	internal var timeInterval: TimeInterval {
		#if swift(>=3.2)
			switch self {
			case let .seconds(s):
				return TimeInterval(s)
			case let .milliseconds(ms):
				return TimeInterval(TimeInterval(ms) / 1000.0)
			case let .microseconds(us):
				return TimeInterval(Int64(us) * Int64(NSEC_PER_USEC)) / TimeInterval(NSEC_PER_SEC)
			case let .nanoseconds(ns):
				return TimeInterval(ns) / TimeInterval(NSEC_PER_SEC)
			case .never:
				return .infinity
			}
		#else
			switch self {
			case let .seconds(s):
				return TimeInterval(s)
			case let .milliseconds(ms):
				return TimeInterval(TimeInterval(ms) / 1000.0)
			case let .microseconds(us):
				return TimeInterval(Int64(us) * Int64(NSEC_PER_USEC)) / TimeInterval(NSEC_PER_SEC)
			case let .nanoseconds(ns):
				return TimeInterval(ns) / TimeInterval(NSEC_PER_SEC)
			}
		#endif
	}

	// This was added purely so that our test scheduler to "go backwards" in
	// time. See `TestScheduler.rewind(by interval: DispatchTimeInterval)`.
	internal static prefix func -(lhs: DispatchTimeInterval) -> DispatchTimeInterval {
		#if swift(>=3.2)
			switch lhs {
			case let .seconds(s):
				return .seconds(-s)
			case let .milliseconds(ms):
				return .milliseconds(-ms)
			case let .microseconds(us):
				return .microseconds(-us)
			case let .nanoseconds(ns):
				return .nanoseconds(-ns)
			case .never:
				return .never
			}
		#else
			switch lhs {
			case let .seconds(s):
				return .seconds(-s)
			case let .milliseconds(ms):
				return .milliseconds(-ms)
			case let .microseconds(us):
				return .microseconds(-us)
			case let .nanoseconds(ns):
				return .nanoseconds(-ns)
			}
		#endif
	}

	/// Scales a time interval by the given scalar specified in `rhs`.
	///
	/// - note: This method is only used internally to "scale down" a time 
	///			interval. Specifically it's used only to scale intervals to 10% 
	///			of their original value for the default `leeway` parameter in 
	///			`Scheduler.schedule(after:action:)` schedule and similar
	///			other methods.
	///
	///			If seconds is over 200,000, 10% is ~2,000, and hence we end up
	///			with a value of ~2,000,000,000. Not quite overflowing a signed
	///			integer on 32-bit platforms, but close.
	///
	///			Even still, 200,000 seconds should be a rarely (if ever)
	///			specified interval for our APIs. And even then, folks should be
	///			smart and specify their own `leeway` parameter.
	///
	/// - returns: Scaled interval in microseconds
	internal static func *(lhs: DispatchTimeInterval, rhs: Double) -> DispatchTimeInterval {
		let seconds = lhs.timeInterval * rhs
		return .microseconds(Int(seconds * 1000 * 1000))
	}
}
