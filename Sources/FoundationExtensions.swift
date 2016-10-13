//
//  FoundationExtensions.swift
//  ReactiveSwift
//
//  Created by Justin Spahr-Summers on 2014-10-19.
//  Copyright (c) 2014 GitHub. All rights reserved.
//

import Foundation
import enum Result.NoError

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

			return ActionDisposable {
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
	public func data(with request: URLRequest) -> SignalProducer<(Data, URLResponse), NSError> {
		return SignalProducer { [base = self.base] observer, disposable in
			let task = base.dataTask(with: request) { data, response, error in
				if let data = data, let response = response {
					observer.send(value: (data, response))
					observer.sendCompleted()
				} else {
					observer.send(error: error as NSError? ?? defaultSessionError)
				}
			}

			disposable += {
				task.cancel()
			}
			task.resume()
		}
	}
}
