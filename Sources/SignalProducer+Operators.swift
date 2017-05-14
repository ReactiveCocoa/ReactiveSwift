import Result
import Dispatch
import Foundation

extension SignalProducer {
	/// Create a `SignalProducer` that will attempt the given operation once for
	/// each invocation of `start()`.
	///
	/// Upon success, the started signal will send the resulting value then
	/// complete. Upon failure, the started signal will fail with the error that
	/// occurred.
	///
	/// - parameters:
	///   - operation: A closure that returns instance of `Result`.
	///
	/// - returns: A `SignalProducer` that will forward `success`ful `result` as
	///            `value` event and then complete or `failed` event if `result`
	///            is a `failure`.
	public static func attempt(_ operation: @escaping () -> Result<Value, Error>) -> SignalProducer<Value, Error> {
		return SignalProducer<Value, Error> { observer, disposable in
			operation().analysis(ifSuccess: { value in
				observer.send(value: value)
				observer.sendCompleted()
			}, ifFailure: { error in
				observer.send(error: error)
			})
		}
	}
}

// FIXME: SWIFT_COMPILER_ISSUE
//
// One of the `SignalProducer.attempt` overloads is kept in the protocol to
// mitigate an overloading issue. Moving them back to the concrete type would be
// a binary-breaking, source-compatible change.

extension SignalProducerProtocol where Error == AnyError {
	/// Create a `SignalProducer` that, when start, would invoke a throwable action.
	///
	/// The produced `Signal` would forward the result and complete if the action
	/// succeeds. Otherwise, the produced signal would propagate the thrown error and
	/// terminate.
	///
	/// - parameters:
	///   - action: A throwable closure which yields a value.
	///
	/// - returns: A producer that yields the result or the error of the given action.
	public static func attempt(_ action: @escaping () throws -> Value) -> SignalProducer<Value, AnyError> {
		return .attempt {
			ReactiveSwift.materialize {
				try action()
			}
		}
	}
}

extension SignalProducer {
	/// Injects side effects to be performed upon the specified producer events.
	///
	/// - note: In a composed producer, `starting` is invoked in the reverse
	///         direction of the flow of events.
	///
	/// - parameters:
	///   - starting: A closure that is invoked before the producer is started.
	///   - started: A closure that is invoked after the producer is started.
	///   - event: A closure that accepts an event and is invoked on every
	///            received event.
	///   - failed: A closure that accepts error object and is invoked for
	///             `failed` event.
	///   - completed: A closure that is invoked for `completed` event.
	///   - interrupted: A closure that is invoked for `interrupted` event.
	///   - terminated: A closure that is invoked for any terminating event.
	///   - disposed: A closure added as disposable when signal completes.
	///   - value: A closure that accepts a value from `value` event.
	///
	/// - returns: A producer with attached side-effects for given event cases.
	public func on(
		starting: (() -> Void)? = nil,
		started: (() -> Void)? = nil,
		event: ((ProducedSignal.Event) -> Void)? = nil,
		failed: ((Error) -> Void)? = nil,
		completed: (() -> Void)? = nil,
		interrupted: (() -> Void)? = nil,
		terminated: (() -> Void)? = nil,
		disposed: (() -> Void)? = nil,
		value: ((Value) -> Void)? = nil
		) -> SignalProducer<Value, Error> {
		return SignalProducer { observer, compositeDisposable in
			starting?()
			defer { started?() }

			self.startWithSignal { signal, disposable in
				compositeDisposable += disposable
				signal
					.on(
						event: event,
						failed: failed,
						completed: completed,
						interrupted: interrupted,
						terminated: terminated,
						disposed: disposed,
						value: value
					)
					.observe(observer)
			}
		}
	}

	/// Start the returned producer on the given `Scheduler`.
	///
	/// - note: This implies that any side effects embedded in the producer will
	///         be performed on the given scheduler as well.
	///
	/// - note: Events may still be sent upon other schedulers — this merely
	///         affects where the `start()` method is run.
	///
	/// - parameters:
	///   - scheduler: A scheduler to deliver events on.
	///
	/// - returns: A producer that will deliver events on given `scheduler` when
	///            started.
	public func start(on scheduler: Scheduler) -> SignalProducer<Value, Error> {
		return SignalProducer { observer, compositeDisposable in
			compositeDisposable += scheduler.schedule {
				self.startWithSignal { signal, signalDisposable in
					compositeDisposable += signalDisposable
					signal.observe(observer)
				}
			}
		}
	}
}

extension SignalProducer {
	/// Repeat `self` a total of `count` times. In other words, start producer
	/// `count` number of times, each one after previously started producer
	/// completes.
	///
	/// - note: Repeating `1` time results in an equivalent signal producer.
	///
	/// - note: Repeating `0` times results in a producer that instantly
	///         completes.
	///
	/// - precondition: `count` must be non-negative integer.
	///
	/// - parameters:
	///   - count: Number of repetitions.
	///
	/// - returns: A signal producer start sequentially starts `self` after
	///            previously started producer completes.
	public func `repeat`(_ count: Int) -> SignalProducer<Value, Error> {
		precondition(count >= 0)

		if count == 0 {
			return .empty
		} else if count == 1 {
			return producer
		}

		return SignalProducer { observer, disposable in
			let serialDisposable = SerialDisposable()
			disposable += serialDisposable

			func iterate(_ current: Int) {
				self.startWithSignal { signal, signalDisposable in
					serialDisposable.inner = signalDisposable

					signal.observe { event in
						if case .completed = event {
							let remainingTimes = current - 1
							if remainingTimes > 0 {
								iterate(remainingTimes)
							} else {
								observer.sendCompleted()
							}
						} else {
							observer.action(event)
						}
					}
				}
			}

			iterate(count)
		}
	}

	/// Ignore failures up to `count` times.
	///
	/// - precondition: `count` must be non-negative integer.
	///
	/// - parameters:
	///   - count: Number of retries.
	///
	/// - returns: A signal producer that restarts up to `count` times.
	public func retry(upTo count: Int) -> SignalProducer<Value, Error> {
		precondition(count >= 0)

		if count == 0 {
			return producer
		} else {
			return flatMapError { _ in
				self.retry(upTo: count - 1)
			}
		}
	}

	/// Wait for completion of `self`, *then* forward all events from
	/// `replacement`. Any failure or interruption sent from `self` is
	/// forwarded immediately, in which case `replacement` will not be started,
	/// and none of its events will be be forwarded.
	///
	/// - note: All values sent from `self` are ignored.
	///
	/// - parameters:
	///   - replacement: A producer to start when `self` completes.
	///
	/// - returns: A producer that sends events from `self` and then from
	///            `replacement` when `self` completes.
	public func then<U>(_ replacement: SignalProducer<U, NoError>) -> SignalProducer<U, Error> {
		return _then(replacement.promoteErrors(Error.self))
	}

	/// Wait for completion of `self`, *then* forward all events from
	/// `replacement`. Any failure or interruption sent from `self` is
	/// forwarded immediately, in which case `replacement` will not be started,
	/// and none of its events will be be forwarded.
	///
	/// - note: All values sent from `self` are ignored.
	///
	/// - parameters:
	///   - replacement: A producer to start when `self` completes.
	///
	/// - returns: A producer that sends events from `self` and then from
	///            `replacement` when `self` completes.
	public func then<U>(_ replacement: SignalProducer<U, Error>) -> SignalProducer<U, Error> {
		return _then(replacement)
	}

	// NOTE: The overload below is added to disambiguate compile-time selection of
	//       `then(_:)`.

	/// Wait for completion of `self`, *then* forward all events from
	/// `replacement`. Any failure or interruption sent from `self` is
	/// forwarded immediately, in which case `replacement` will not be started,
	/// and none of its events will be be forwarded.
	///
	/// - note: All values sent from `self` are ignored.
	///
	/// - parameters:
	///   - replacement: A producer to start when `self` completes.
	///
	/// - returns: A producer that sends events from `self` and then from
	///            `replacement` when `self` completes.
	public func then(_ replacement: SignalProducer<Value, Error>) -> SignalProducer<Value, Error> {
		return _then(replacement)
	}

	// NOTE: The method below is the shared implementation of `then(_:)`. The underscore
	//       prefix is added to avoid self referencing in `then(_:)` overloads with
	//       regard to the most specific rule of overload selection in Swift.

	internal func _then<U>(_ replacement: SignalProducer<U, Error>) -> SignalProducer<U, Error> {
		return SignalProducer<U, Error> { observer, observerDisposable in
			self.startWithSignal { signal, signalDisposable in
				observerDisposable += signalDisposable

				signal.observe { event in
					switch event {
					case let .failed(error):
						observer.send(error: error)
					case .completed:
						observerDisposable += replacement.start(observer)
					case .interrupted:
						observer.sendInterrupted()
					case .value:
						break
					}
				}
			}
		}
	}
}

extension SignalProducer where Error == NoError {
	/// Wait for completion of `self`, *then* forward all events from
	/// `replacement`.
	///
	/// - note: All values sent from `self` are ignored.
	///
	/// - parameters:
	///   - replacement: A producer to start when `self` completes.
	///
	/// - returns: A producer that sends events from `self` and then from
	///            `replacement` when `self` completes.
	public func then<U, NewError: Swift.Error>(_ replacement: SignalProducer<U, NewError>) -> SignalProducer<U, NewError> {
		return promoteErrors(NewError.self)._then(replacement)
	}

	// NOTE: The overload below is added to disambiguate compile-time selection of
	//       `then(_:)`.

	/// Wait for completion of `self`, *then* forward all events from
	/// `replacement`.
	///
	/// - note: All values sent from `self` are ignored.
	///
	/// - parameters:
	///   - replacement: A producer to start when `self` completes.
	///
	/// - returns: A producer that sends events from `self` and then from
	///            `replacement` when `self` completes.
	public func then<U>(_ replacement: SignalProducer<U, NoError>) -> SignalProducer<U, NoError> {
		return _then(replacement)
	}
}

extension SignalProducer {
	/// Start the producer, then block, waiting for the first value.
	///
	/// When a single value or error is sent, the returned `Result` will
	/// represent those cases. However, when no values are sent, `nil` will be
	/// returned.
	///
	/// - returns: Result when single `value` or `failed` event is received.
	///            `nil` when no events are received.
	public func first() -> Result<Value, Error>? {
		return take(first: 1).single()
	}

	/// Start the producer, then block, waiting for events: `value` and
	/// `completed`.
	///
	/// When a single value or error is sent, the returned `Result` will
	/// represent those cases. However, when no values are sent, or when more
	/// than one value is sent, `nil` will be returned.
	///
	/// - returns: Result when single `value` or `failed` event is received.
	///            `nil` when 0 or more than 1 events are received.
	public func single() -> Result<Value, Error>? {
		let semaphore = DispatchSemaphore(value: 0)
		var result: Result<Value, Error>?

		take(first: 2).start { event in
			switch event {
			case let .value(value):
				if result != nil {
					// Move into failure state after recieving another value.
					result = nil
					return
				}
				result = .success(value)
			case let .failed(error):
				result = .failure(error)
				semaphore.signal()
			case .completed, .interrupted:
				semaphore.signal()
			}
		}

		semaphore.wait()
		return result
	}

	/// Start the producer, then block, waiting for the last value.
	///
	/// When a single value or error is sent, the returned `Result` will
	/// represent those cases. However, when no values are sent, `nil` will be
	/// returned.
	///
	/// - returns: Result when single `value` or `failed` event is received.
	///            `nil` when no events are received.
	public func last() -> Result<Value, Error>? {
		return take(last: 1).single()
	}

	/// Starts the producer, then blocks, waiting for completion.
	///
	/// When a completion or error is sent, the returned `Result` will represent
	/// those cases.
	///
	/// - returns: Result when single `completion` or `failed` event is
	///            received.
	public func wait() -> Result<(), Error> {
		return then(SignalProducer<(), Error>(value: ())).last() ?? .success(())
	}

	/// Creates a new `SignalProducer` that will multicast values emitted by
	/// the underlying producer, up to `capacity`.
	/// This means that all clients of this `SignalProducer` will see the same
	/// version of the emitted values/errors.
	///
	/// The underlying `SignalProducer` will not be started until `self` is
	/// started for the first time. When subscribing to this producer, all
	/// previous values (up to `capacity`) will be emitted, followed by any new
	/// values.
	///
	/// If you find yourself needing *the current value* (the last buffered
	/// value) you should consider using `PropertyType` instead, which, unlike
	/// this operator, will guarantee at compile time that there's always a
	/// buffered value. This operator is not recommended in most cases, as it
	/// will introduce an implicit relationship between the original client and
	/// the rest, so consider alternatives like `PropertyType`, or representing
	/// your stream using a `Signal` instead.
	///
	/// This operator is only recommended when you absolutely need to introduce
	/// a layer of caching in front of another `SignalProducer`.
	///
	/// - precondition: `capacity` must be non-negative integer.
	///
	/// - parameters:
	///   - capacity: Number of values to hold.
	///
	/// - returns: A caching producer that will hold up to last `capacity`
	///            values.
	public func replayLazily(upTo capacity: Int) -> SignalProducer<Value, Error> {
		precondition(capacity >= 0, "Invalid capacity: \(capacity)")

		// This will go "out of scope" when the returned `SignalProducer` goes
		// out of scope. This lets us know when we're supposed to dispose the
		// underlying producer. This is necessary because `struct`s don't have
		// `deinit`.
		let lifetimeToken = Lifetime.Token()
		let lifetime = Lifetime(lifetimeToken)

		let state = Atomic(ReplayState<Value, Error>(upTo: capacity))

		let start: Atomic<(() -> Void)?> = Atomic {
			// Start the underlying producer.
			self
				.take(during: lifetime)
				.start { event in
					let observers: Bag<Signal<Value, Error>.Observer>? = state.modify { state in
						defer { state.enqueue(event) }
						return state.observers
					}
					observers?.forEach { $0.action(event) }
			}
		}

		return SignalProducer { observer, disposable in
			// Don't dispose of the original producer until all observers
			// have terminated.
			disposable += { _ = lifetimeToken }

			while true {
				var result: Result<Bag<Signal<Value, Error>.Observer>.Token?, ReplayError<Value>>!
				state.modify {
					result = $0.observe(observer)
				}

				switch result! {
				case let .success(token):
					if let token = token {
						disposable += {
							state.modify {
								$0.removeObserver(using: token)
							}
						}
					}

					// Start the underlying producer if it has never been started.
					start.swap(nil)?()

					// Terminate the replay loop.
					return

				case let .failure(error):
					error.values.forEach(observer.send(value:))
				}
			}
		}
	}
}

/// Represents a recoverable error of an observer not being ready for an
/// attachment to a `ReplayState`, and the observer should replay the supplied
/// values before attempting to observe again.
private struct ReplayError<Value>: Error {
	/// The values that should be replayed by the observer.
	let values: [Value]
}

private struct ReplayState<Value, Error: Swift.Error> {
	let capacity: Int

	/// All cached values.
	var values: [Value] = []

	/// A termination event emitted by the underlying producer.
	///
	/// This will be nil if termination has not occurred.
	var terminationEvent: Signal<Value, Error>.Event?

	/// The observers currently attached to the caching producer, or `nil` if the
	/// caching producer was terminated.
	var observers: Bag<Signal<Value, Error>.Observer>? = Bag()

	/// The set of in-flight replay buffers.
	var replayBuffers: [ObjectIdentifier: [Value]] = [:]

	/// Initialize the replay state.
	///
	/// - parameters:
	///   - capacity: The maximum amount of values which can be cached by the
	///               replay state.
	init(upTo capacity: Int) {
		self.capacity = capacity
	}

	/// Attempt to observe the replay state.
	///
	/// - warning: Repeatedly observing the replay state with the same observer
	///            should be avoided.
	///
	/// - parameters:
	///   - observer: The observer to be registered.
	///
	/// - returns: If the observer is successfully attached, a `Result.success`
	///            with the corresponding removal token would be returned.
	///            Otherwise, a `Result.failure` with a `ReplayError` would be
	///            returned.
	mutating func observe(_ observer: Signal<Value, Error>.Observer) -> Result<Bag<Signal<Value, Error>.Observer>.Token?, ReplayError<Value>> {
		// Since the only use case is `replayLazily`, which always creates a unique
		// `Observer` for every produced signal, we can use the ObjectIdentifier of
		// the `Observer` to track them directly.
		let id = ObjectIdentifier(observer)

		switch replayBuffers[id] {
		case .none where !values.isEmpty:
			// No in-flight replay buffers was found, but the `ReplayState` has one or
			// more cached values in the `ReplayState`. The observer should replay
			// them before attempting to observe again.
			replayBuffers[id] = []
			return .failure(ReplayError(values: values))

		case let .some(buffer) where !buffer.isEmpty:
			// An in-flight replay buffer was found with one or more buffered values.
			// The observer should replay them before attempting to observe again.
			defer { replayBuffers[id] = [] }
			return .failure(ReplayError(values: buffer))

		case let .some(buffer) where buffer.isEmpty:
			// Since an in-flight but empty replay buffer was found, the observer is
			// ready to be attached to the `ReplayState`.
			replayBuffers.removeValue(forKey: id)

		default:
			// No values has to be replayed. The observer is ready to be attached to
			// the `ReplayState`.
			break
		}

		if let event = terminationEvent {
			observer.action(event)
		}

		return .success(observers?.insert(observer))
	}

	/// Enqueue the supplied event to the replay state.
	///
	/// - parameter:
	///   - event: The event to be cached.
	mutating func enqueue(_ event: Signal<Value, Error>.Event) {
		switch event {
		case let .value(value):
			for key in replayBuffers.keys {
				replayBuffers[key]!.append(value)
			}

			switch capacity {
			case 0:
				// With a capacity of zero, `state.values` can never be filled.
				break

			case 1:
				values = [value]

			default:
				values.append(value)

				let overflow = values.count - capacity
				if overflow > 0 {
					values.removeFirst(overflow)
				}
			}

		case .completed, .failed, .interrupted:
			// Disconnect all observers and prevent future attachments.
			terminationEvent = event
			observers = nil
		}
	}

	/// Remove the observer represented by the supplied token.
	///
	/// - parameters:
	///   - token: The token of the observer to be removed.
	mutating func removeObserver(using token: Bag<Signal<Value, Error>.Observer>.Token) {
		observers?.remove(using: token)
	}
}

extension SignalProducer where Value == Date, Error == NoError {
	/// Create a repeating timer of the given interval, with a reasonable default
	/// leeway, sending updates on the given scheduler.
	///
	/// - note: This timer will never complete naturally, so all invocations of
	///         `start()` must be disposed to avoid leaks.
	///
	/// - precondition: `interval` must be non-negative number.
	///
	///	- note: If you plan to specify an `interval` value greater than 200,000
	///			seconds, use `timer(interval:on:leeway:)` instead
	///			and specify your own `leeway` value to avoid potential overflow.
	///
	/// - parameters:
	///   - interval: An interval between invocations.
	///   - scheduler: A scheduler to deliver events on.
	///
	/// - returns: A producer that sends `NSDate` values every `interval` seconds.
	public static func timer(interval: DispatchTimeInterval, on scheduler: DateScheduler) -> SignalProducer<Value, Error> {
		// Apple's "Power Efficiency Guide for Mac Apps" recommends a leeway of
		// at least 10% of the timer interval.
		return timer(interval: interval, on: scheduler, leeway: interval * 0.1)
	}

	/// Creates a repeating timer of the given interval, sending updates on the
	/// given scheduler.
	///
	/// - note: This timer will never complete naturally, so all invocations of
	///         `start()` must be disposed to avoid leaks.
	///
	/// - precondition: `interval` must be non-negative number.
	///
	/// - precondition: `leeway` must be non-negative number.
	///
	/// - parameters:
	///   - interval: An interval between invocations.
	///   - scheduler: A scheduler to deliver events on.
	///   - leeway: Interval leeway. Apple's "Power Efficiency Guide for Mac Apps"
	///             recommends a leeway of at least 10% of the timer interval.
	///
	/// - returns: A producer that sends `NSDate` values every `interval` seconds.
	public static func timer(interval: DispatchTimeInterval, on scheduler: DateScheduler, leeway: DispatchTimeInterval) -> SignalProducer<Value, Error> {
		precondition(interval.timeInterval >= 0)
		precondition(leeway.timeInterval >= 0)

		return SignalProducer { observer, compositeDisposable in
			compositeDisposable += scheduler.schedule(after: scheduler.currentDate.addingTimeInterval(interval),
			                                          interval: interval,
			                                          leeway: leeway,
			                                          action: { observer.send(value: scheduler.currentDate) })
		}
	}
}
