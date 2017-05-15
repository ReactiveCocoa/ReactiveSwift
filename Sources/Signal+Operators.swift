import Result
import Foundation

extension Signal {
	/// Map each value in the signal to a new value.
	///
	/// - parameters:
	///   - transform: A closure that accepts a value from the `value` event and
	///                returns a new value.
	///
	/// - returns: A signal that will send new values.
	public func map<U>(_ transform: @escaping (Value) -> U) -> Signal<U, Error> {
		return Signal<U, Error> { observer in
			return self.observe { event in
				observer.action(event.map(transform))
			}
		}
	}

	/// Map errors in the signal to a new error.
	///
	/// - parameters:
	///   - transform: A closure that accepts current error object and returns
	///                a new type of error object.
	///
	/// - returns: A signal that will send new type of errors.
	public func mapError<F>(_ transform: @escaping (Error) -> F) -> Signal<Value, F> {
		return Signal<Value, F> { observer in
			return self.observe { event in
				observer.action(event.mapError(transform))
			}
		}
	}

	/// Maps each value in the signal to a new value, lazily evaluating the
	/// supplied transformation on the specified scheduler.
	///
	/// - important: Unlike `map`, there is not a 1-1 mapping between incoming
	///              values, and values sent on the returned signal. If
	///              `scheduler` has not yet scheduled `transform` for
	///              execution, then each new value will replace the last one as
	///              the parameter to `transform` once it is finally executed.
	///
	/// - parameters:
	///   - transform: The closure used to obtain the returned value from this
	///                signal's underlying value.
	///
	/// - returns: A signal that sends values obtained using `transform` as this
	///            signal sends values.
	public func lazyMap<U>(on scheduler: Scheduler, transform: @escaping (Value) -> U) -> Signal<U, Error> {
		return flatMap(.latest) { value in
			return SignalProducer({ transform(value) })
				.start(on: scheduler)
		}
	}

	/// Preserve only values which pass the given closure.
	///
	/// - parameters:
	///   - isIncluded: A closure to determine whether a value from `self` should be
	///                 included in the returned `Signal`.
	///
	/// - returns: A signal that forwards the values passing the given closure.
	public func filter(_ isIncluded: @escaping (Value) -> Bool) -> Signal<Value, Error> {
		return Signal { observer in
			return self.observe { (event: Event) -> Void in
				guard let value = event.value else {
					observer.action(event)
					return
				}

				if isIncluded(value) {
					observer.send(value: value)
				}
			}
		}
	}

	/// Applies `transform` to values from `signal` and forwards values with non `nil` results unwrapped.
	/// - parameters:
	///   - transform: A closure that accepts a value from the `value` event and
	///                returns a new optional value.
	///
	/// - returns: A signal that will send new values, that are non `nil` after the transformation.
	public func filterMap<U>(_ transform: @escaping (Value) -> U?) -> Signal<U, Error> {
		return Signal<U, Error> { observer in
			return self.observe { (event: Event) -> Void in
				switch event {
				case let .value(value):
					if let mapped = transform(value) {
						observer.send(value: mapped)
					}
				case let .failed(error):
					observer.send(error: error)
				case .completed:
					observer.sendCompleted()
				case .interrupted:
					observer.sendInterrupted()
				}
			}
		}
	}
}

extension Signal where Value: OptionalProtocol {
	/// Unwrap non-`nil` values and forward them on the returned signal, `nil`
	/// values are dropped.
	///
	/// - returns: A signal that sends only non-nil values.
	public func skipNil() -> Signal<Value.Wrapped, Error> {
		return filterMap { $0.optional }
	}
}

extension Signal {
	/// Take up to `n` values from the signal and then complete.
	///
	/// - precondition: `count` must be non-negative number.
	///
	/// - parameters:
	///   - count: A number of values to take from the signal.
	///
	/// - returns: A signal that will yield the first `count` values from `self`
	public func take(first count: Int) -> Signal<Value, Error> {
		precondition(count >= 0)

		return Signal { observer in
			if count == 0 {
				observer.sendCompleted()
				return nil
			}

			var taken = 0

			return self.observe { event in
				guard let value = event.value else {
					observer.action(event)
					return
				}

				if taken < count {
					taken += 1
					observer.send(value: value)
				}

				if taken == count {
					observer.sendCompleted()
				}
			}
		}
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

extension Signal {
	/// Collect all values sent by the signal then forward them as a single
	/// array and complete.
	///
	/// - note: When `self` completes without collecting any value, it will send
	///         an empty array of values.
	///
	/// - returns: A signal that will yield an array of values when `self`
	///            completes.
	public func collect() -> Signal<[Value], Error> {
		return collect { _,_ in false }
	}

	/// Collect at most `count` values from `self`, forward them as a single
	/// array and complete.
	///
	/// - note: When the count is reached the array is sent and the signal
	///         starts over yielding a new array of values.
	///
	/// - note: When `self` completes any remaining values will be sent, the
	///         last array may not have `count` values. Alternatively, if were
	///         not collected any values will sent an empty array of values.
	///
	/// - precondition: `count` should be greater than zero.
	///
	public func collect(count: Int) -> Signal<[Value], Error> {
		precondition(count > 0)
		return collect { values in values.count == count }
	}

	/// Collect values from `self`, and emit them if the predicate passes.
	///
	/// When `self` completes any remaining values will be sent, regardless of the
	/// collected values matching `shouldEmit` or not.
	///
	/// If `self` completes without having emitted any value, an empty array would be
	/// emitted, followed by the completion of the returned `Signal`.
	///
	/// ````
	/// let (signal, observer) = Signal<Int, NoError>.pipe()
	///
	/// signal
	///     .collect { values in values.reduce(0, combine: +) == 8 }
	///     .observeValues { print($0) }
	///
	/// observer.send(value: 1)
	/// observer.send(value: 3)
	/// observer.send(value: 4)
	/// observer.send(value: 7)
	/// observer.send(value: 1)
	/// observer.send(value: 5)
	/// observer.send(value: 6)
	/// observer.sendCompleted()
	///
	/// // Output:
	/// // [1, 3, 4]
	/// // [7, 1]
	/// // [5, 6]
	/// ````
	///
	/// - parameters:
	///   - shouldEmit: A closure to determine, when every time a new value is received,
	///                 whether the collected values should be emitted. The new value
	///                 is included in the collected values.
	///
	/// - returns: A signal of arrays of values, as instructed by the `shouldEmit`
	///            closure.
	public func collect(_ shouldEmit: @escaping (_ collectedValues: [Value]) -> Bool) -> Signal<[Value], Error> {
		return Signal<[Value], Error> { observer in
			let state = CollectState<Value>()

			return self.observe { event in
				switch event {
				case let .value(value):
					state.append(value)
					if shouldEmit(state.values) {
						observer.send(value: state.values)
						state.flush()
					}
				case .completed:
					if !state.isEmpty {
						observer.send(value: state.values)
					}
					observer.sendCompleted()
				case let .failed(error):
					observer.send(error: error)
				case .interrupted:
					observer.sendInterrupted()
				}
			}
		}
	}

	/// Collect values from `self`, and emit them if the predicate passes.
	///
	/// When `self` completes any remaining values will be sent, regardless of the
	/// collected values matching `shouldEmit` or not.
	///
	/// If `self` completes without having emitted any value, an empty array would be
	/// emitted, followed by the completion of the returned `Signal`.
	///
	/// ````
	/// let (signal, observer) = Signal<Int, NoError>.pipe()
	///
	/// signal
	///     .collect { values, value in value == 7 }
	///     .observeValues { print($0) }
	///
	/// observer.send(value: 1)
	/// observer.send(value: 1)
	/// observer.send(value: 7)
	/// observer.send(value: 7)
	/// observer.send(value: 5)
	/// observer.send(value: 6)
	/// observer.sendCompleted()
	///
	/// // Output:
	/// // [1, 1]
	/// // [7]
	/// // [7, 5, 6]
	/// ````
	///
	/// - parameters:
	///   - shouldEmit: A closure to determine, when every time a new value is received,
	///                 whether the collected values should be emitted. The new value
	///                 is **not** included in the collected values, and is included when
	///                 the next value is received.
	///
	/// - returns: A signal of arrays of values, as instructed by the `shouldEmit`
	///            closure.
	public func collect(_ shouldEmit: @escaping (_ collected: [Value], _ latest: Value) -> Bool) -> Signal<[Value], Error> {
		return Signal<[Value], Error> { observer in
			let state = CollectState<Value>()

			return self.observe { event in
				switch event {
				case let .value(value):
					if shouldEmit(state.values, value) {
						observer.send(value: state.values)
						state.flush()
					}
					state.append(value)
				case .completed:
					if !state.isEmpty {
						observer.send(value: state.values)
					}
					observer.sendCompleted()
				case let .failed(error):
					observer.send(error: error)
				case .interrupted:
					observer.sendInterrupted()
				}
			}
		}
	}

	/// Forward all events onto the given scheduler, instead of whichever
	/// scheduler they originally arrived upon.
	///
	/// - parameters:
	///   - scheduler: A scheduler to deliver events on.
	///
	/// - returns: A signal that will yield `self` values on provided scheduler.
	public func observe(on scheduler: Scheduler) -> Signal<Value, Error> {
		return Signal { observer in
			return self.observe { event in
				scheduler.schedule {
					observer.action(event)
				}
			}
		}
	}
}

extension Signal {
	/// Combine the latest value of the receiver with the latest value from the
	/// given signal.
	///
	/// - note: The returned signal will not send a value until both inputs have
	///         sent at least one value each.
	///
	/// - note: If either signal is interrupted, the returned signal will also
	///         be interrupted.
	///
	/// - note: The returned signal will not complete until both inputs
	///         complete.
	///
	/// - parameters:
	///   - otherSignal: A signal to combine `self`'s value with.
	///
	/// - returns: A signal that will yield a tuple containing values of `self`
	///            and given signal.
	public func combineLatest<U>(with other: Signal<U, Error>) -> Signal<(Value, U), Error> {
		return Signal.combineLatest(self, other)
	}

	/// Delay `value` and `completed` events by the given interval, forwarding
	/// them on the given scheduler.
	///
	/// - note: failed and `interrupted` events are always scheduled
	///         immediately.
	///
	/// - precondition: `interval` must be non-negative number.
	///
	/// - parameters:
	///   - interval: Interval to delay `value` and `completed` events by.
	///   - scheduler: A scheduler to deliver delayed events on.
	///
	/// - returns: A signal that will delay `value` and `completed` events and
	///            will yield them on given scheduler.
	public func delay(_ interval: TimeInterval, on scheduler: DateScheduler) -> Signal<Value, Error> {
		precondition(interval >= 0)

		return Signal { observer in
			return self.observe { event in
				switch event {
				case .failed, .interrupted:
					scheduler.schedule {
						observer.action(event)
					}

				case .value, .completed:
					let date = scheduler.currentDate.addingTimeInterval(interval)
					scheduler.schedule(after: date) {
						observer.action(event)
					}
				}
			}
		}
	}

	/// Skip first `count` number of values then act as usual.
	///
	/// - precondition: `count` must be non-negative number.
	///
	/// - parameters:
	///   - count: A number of values to skip.
	///
	/// - returns:  A signal that will skip the first `count` values, then
	///             forward everything afterward.
	public func skip(first count: Int) -> Signal<Value, Error> {
		precondition(count >= 0)

		if count == 0 {
			return signal
		}

		return Signal { observer in
			var skipped = 0

			return self.observe { event in
				if case .value = event, skipped < count {
					skipped += 1
				} else {
					observer.action(event)
				}
			}
		}
	}

	/// Treat all Events from `self` as plain values, allowing them to be
	/// manipulated just like any other value.
	///
	/// In other words, this brings Events “into the monad”.
	///
	/// - note: When a Completed or Failed event is received, the resulting
	///         signal will send the Event itself and then complete. When an
	///         Interrupted event is received, the resulting signal will send
	///         the Event itself and then interrupt.
	///
	/// - returns: A signal that sends events as its values.
	public func materialize() -> Signal<Event, NoError> {
		return Signal<Event, NoError> { observer in
			return self.observe { event in
				observer.send(value: event)

				switch event {
				case .interrupted:
					observer.sendInterrupted()

				case .completed, .failed:
					observer.sendCompleted()

				case .value:
					break
				}
			}
		}
	}
}

extension Signal where Value: EventProtocol, Error == NoError {
	/// Translate a signal of `Event` _values_ into a signal of those events
	/// themselves.
	///
	/// - returns: A signal that sends values carried by `self` events.
	public func dematerialize() -> Signal<Value.Value, Value.Error> {
		return Signal<Value.Value, Value.Error> { observer in
			return self.observe { event in
				switch event {
				case let .value(innerEvent):
					observer.action(innerEvent.event)

				case .failed:
					fatalError("NoError is impossible to construct")

				case .completed:
					observer.sendCompleted()

				case .interrupted:
					observer.sendInterrupted()
				}
			}
		}
	}
}

extension Signal {
	/// Inject side effects to be performed upon the specified signal events.
	///
	/// - parameters:
	///   - event: A closure that accepts an event and is invoked on every
	///            received event.
	///   - failed: A closure that accepts error object and is invoked for
	///             failed event.
	///   - completed: A closure that is invoked for `completed` event.
	///   - interrupted: A closure that is invoked for `interrupted` event.
	///   - terminated: A closure that is invoked for any terminating event.
	///   - disposed: A closure added as disposable when signal completes.
	///   - value: A closure that accepts a value from `value` event.
	///
	/// - returns: A signal with attached side-effects for given event cases.
	public func on(
		event: ((Event) -> Void)? = nil,
		failed: ((Error) -> Void)? = nil,
		completed: (() -> Void)? = nil,
		interrupted: (() -> Void)? = nil,
		terminated: (() -> Void)? = nil,
		disposed: (() -> Void)? = nil,
		value: ((Value) -> Void)? = nil
		) -> Signal<Value, Error> {
		return Signal { observer in
			let disposable = CompositeDisposable()

			_ = disposed.map(disposable.add)

			disposable += signal.observe { receivedEvent in
				event?(receivedEvent)

				switch receivedEvent {
				case let .value(v):
					value?(v)

				case let .failed(error):
					failed?(error)

				case .completed:
					completed?()

				case .interrupted:
					interrupted?()
				}

				if receivedEvent.isTerminating {
					terminated?()
				}

				observer.action(receivedEvent)
			}

			return disposable
		}
	}
}

private struct SampleState<Value> {
	var latestValue: Value? = nil
	var isSignalCompleted: Bool = false
	var isSamplerCompleted: Bool = false
}

extension Signal {
	/// Forward the latest value from `self` with the value from `sampler` as a
	/// tuple, only when`sampler` sends a `value` event.
	///
	/// - note: If `sampler` fires before a value has been observed on `self`,
	///         nothing happens.
	///
	/// - parameters:
	///   - sampler: A signal that will trigger the delivery of `value` event
	///              from `self`.
	///
	/// - returns: A signal that will send values from `self` and `sampler`,
	///            sampled (possibly multiple times) by `sampler`, then complete
	///            once both input signals have completed, or interrupt if
	///            either input signal is interrupted.
	public func sample<T>(with sampler: Signal<T, NoError>) -> Signal<(Value, T), Error> {
		return Signal<(Value, T), Error> { observer in
			let state = Atomic(SampleState<Value>())
			let disposable = CompositeDisposable()

			disposable += self.observe { event in
				switch event {
				case let .value(value):
					state.modify {
						$0.latestValue = value
					}

				case let .failed(error):
					observer.send(error: error)

				case .completed:
					let shouldComplete: Bool = state.modify {
						$0.isSignalCompleted = true
						return $0.isSamplerCompleted
					}

					if shouldComplete {
						observer.sendCompleted()
					}

				case .interrupted:
					observer.sendInterrupted()
				}
			}

			disposable += sampler.observe { event in
				switch event {
				case .value(let samplerValue):
					if let value = state.value.latestValue {
						observer.send(value: (value, samplerValue))
					}

				case .completed:
					let shouldComplete: Bool = state.modify {
						$0.isSamplerCompleted = true
						return $0.isSignalCompleted
					}

					if shouldComplete {
						observer.sendCompleted()
					}

				case .interrupted:
					observer.sendInterrupted()

				case .failed:
					break
				}
			}

			return disposable
		}
	}

	/// Forward the latest value from `self` whenever `sampler` sends a `value`
	/// event.
	///
	/// - note: If `sampler` fires before a value has been observed on `self`,
	///         nothing happens.
	///
	/// - parameters:
	///   - sampler: A signal that will trigger the delivery of `value` event
	///              from `self`.
	///
	/// - returns: A signal that will send values from `self`, sampled (possibly
	///            multiple times) by `sampler`, then complete once both input
	///            signals have completed, or interrupt if either input signal
	///            is interrupted.
	public func sample(on sampler: Signal<(), NoError>) -> Signal<Value, Error> {
		return sample(with: sampler)
			.map { $0.0 }
	}

	/// Forward the latest value from `samplee` with the value from `self` as a
	/// tuple, only when `self` sends a `value` event.
	/// This is like a flipped version of `sample(with:)`, but `samplee`'s
	/// terminal events are completely ignored.
	///
	/// - note: If `self` fires before a value has been observed on `samplee`,
	///         nothing happens.
	///
	/// - parameters:
	///   - samplee: A signal whose latest value is sampled by `self`.
	///
	/// - returns: A signal that will send values from `self` and `samplee`,
	///            sampled (possibly multiple times) by `self`, then terminate
	///            once `self` has terminated. **`samplee`'s terminated events
	///            are ignored**.
	public func withLatest<U>(from samplee: Signal<U, NoError>) -> Signal<(Value, U), Error> {
		return Signal<(Value, U), Error> { observer in
			let state = Atomic<U?>(nil)
			let disposable = CompositeDisposable()

			disposable += samplee.observeValues { value in
				state.value = value
			}

			disposable += self.observe { event in
				switch event {
				case let .value(value):
					if let value2 = state.value {
						observer.send(value: (value, value2))
					}
				case .completed:
					observer.sendCompleted()
				case let .failed(error):
					observer.send(error: error)
				case .interrupted:
					observer.sendInterrupted()
				}
			}

			return disposable
		}
	}

	/// Forward the latest value from `samplee` with the value from `self` as a
	/// tuple, only when `self` sends a `value` event.
	/// This is like a flipped version of `sample(with:)`, but `samplee`'s
	/// terminal events are completely ignored.
	///
	/// - note: If `self` fires before a value has been observed on `samplee`,
	///         nothing happens.
	///
	/// - parameters:
	///   - samplee: A producer whose latest value is sampled by `self`.
	///
	/// - returns: A signal that will send values from `self` and `samplee`,
	///            sampled (possibly multiple times) by `self`, then terminate
	///            once `self` has terminated. **`samplee`'s terminated events
	///            are ignored**.
	public func withLatest<U>(from samplee: SignalProducer<U, NoError>) -> Signal<(Value, U), Error> {
		return Signal<(Value, U), Error> { observer in
			let d = CompositeDisposable()
			samplee.startWithSignal { signal, disposable in
				d += disposable
				d += self.withLatest(from: signal).observe(observer)
			}
			return d
		}
	}
}

extension Signal {
	/// Forwards events from `self` until `lifetime` ends, at which point the
	/// returned signal will complete.
	///
	/// - parameters:
	///   - lifetime: A lifetime whose `ended` signal will cause the returned
	///               signal to complete.
	///
	/// - returns: A signal that will deliver events until `lifetime` ends.
	public func take(during lifetime: Lifetime) -> Signal<Value, Error> {
		return Signal<Value, Error> { observer in
			let disposable = CompositeDisposable()
			disposable += self.observe(observer)
			disposable += lifetime.observeEnded(observer.sendCompleted)
			return disposable
		}
	}

	/// Forward events from `self` until `trigger` sends a `value` or
	/// `completed` event, at which point the returned signal will complete.
	///
	/// - parameters:
	///   - trigger: A signal whose `value` or `completed` events will stop the
	///              delivery of `value` events from `self`.
	///
	/// - returns: A signal that will deliver events until `trigger` sends
	///            `value` or `completed` events.
	public func take(until trigger: Signal<(), NoError>) -> Signal<Value, Error> {
		return Signal<Value, Error> { observer in
			let disposable = CompositeDisposable()
			disposable += self.observe(observer)

			disposable += trigger.observe { event in
				switch event {
				case .value, .completed:
					observer.sendCompleted()

				case .failed, .interrupted:
					break
				}
			}

			return disposable
		}
	}

	/// Do not forward any values from `self` until `trigger` sends a `value` or
	/// `completed` event, at which point the returned signal behaves exactly
	/// like `signal`.
	///
	/// - parameters:
	///   - trigger: A signal whose `value` or `completed` events will start the
	///              deliver of events on `self`.
	///
	/// - returns: A signal that will deliver events once the `trigger` sends
	///            `value` or `completed` events.
	public func skip(until trigger: Signal<(), NoError>) -> Signal<Value, Error> {
		return Signal { observer in
			let disposable = SerialDisposable()

			disposable.inner = trigger.observe { event in
				switch event {
				case .value, .completed:
					disposable.inner = self.observe(observer)

				case .failed, .interrupted:
					break
				}
			}

			return disposable
		}
	}

	/// Forward events from `self` with history: values of the returned signal
	/// are a tuples whose first member is the previous value and whose second member
	/// is the current value. `initial` is supplied as the first member when `self`
	/// sends its first value.
	///
	/// - parameters:
	///   - initial: A value that will be combined with the first value sent by
	///              `self`.
	///
	/// - returns: A signal that sends tuples that contain previous and current
	///            sent values of `self`.
	public func combinePrevious(_ initial: Value) -> Signal<(Value, Value), Error> {
		return scan((initial, initial)) { previousCombinedValues, newValue in
			return (previousCombinedValues.1, newValue)
		}
	}


	/// Combine all values from `self`, and forward only the final accumuated result.
	///
	/// See `scan(_:_:)` if the resulting producer needs to forward also the partial
	/// results.
	///
	/// - parameters:
	///   - initialResult: The value to use as the initial accumulating value.
	///   - nextPartialResult: A closure that combines the accumulating value and the
	///                        latest value from `self`. The result would be used in the
	///                        next call of `nextPartialResult`, or emit to the returned
	///                        `Signal` when `self` completes.
	///
	/// - returns: A signal that sends the final result as `self` completes.
	public func reduce<U>(_ initialResult: U, _ nextPartialResult: @escaping (U, Value) -> U) -> Signal<U, Error> {
		return self.reduce(into: initialResult) { accumulator, value in
			accumulator = nextPartialResult(accumulator, value)
		}
	}

	/// Combine all values from `self`, and forward only the final accumuated result.
	///
	/// See `scan(into:_:)` if the resulting producer needs to forward also the partial
	/// results.
	///
	/// - parameters:
	///   - initialResult: The value to use as the initial accumulating value.
	///   - nextPartialResult: A closure that combines the accumulating value and the
	///                        latest value from `self`. The result would be used in the
	///                        next call of `nextPartialResult`, or emit to the returned
	///                        `Signal` when `self` completes.
	///
	/// - returns: A signal that sends the final result as `self` completes.
	public func reduce<U>(into initialResult: U, _ nextPartialResult: @escaping (inout U, Value) -> Void) -> Signal<U, Error> {
		// We need to handle the special case in which `signal` sends no values.
		// We'll do that by sending `initial` on the output signal (before
		// taking the last value).
		let (scannedSignalWithInitialValue, outputSignalObserver) = Signal<U, Error>.pipe()
		let outputSignal = scannedSignalWithInitialValue.take(last: 1)

		// Now that we've got takeLast() listening to the piped signal, send

		// that initial value.
		outputSignalObserver.send(value: initialResult)

		// Pipe the scanned input signal into the output signal.
		self.scan(into: initialResult, nextPartialResult)
			.observe(outputSignalObserver)

		return outputSignal
	}

	/// Combine all values from `self`, and forward the partial results and the final
	/// result.
	///
	/// See `reduce(_:_:)` if the resulting producer needs to forward only the final
	/// result.
	///
	/// - parameters:
	///   - initialResult: The value to use as the initial accumulating value.
	///   - nextPartialResult: A closure that combines the accumulating value and the
	///                        latest value from `self`. The result would be forwarded,
	///                        and would be used in the next call of `nextPartialResult`.
	///
	/// - returns: A signal that sends the partial results of the accumuation, and the
	///            final result as `self` completes.
	public func scan<U>(_ initialResult: U, _ nextPartialResult: @escaping (U, Value) -> U) -> Signal<U, Error> {
		return self.scan(into: initialResult) { accumulator, value in
			accumulator = nextPartialResult(accumulator, value)
		}
	}

	/// Combine all values from `self`, and forward the partial results and the final
	/// result.
	///
	/// See `reduce(into:_:)` if the resulting producer needs to forward only the final
	/// result.
	///
	/// - parameters:
	///   - initialResult: The value to use as the initial accumulating value.
	///   - nextPartialResult: A closure that combines the accumulating value and the
	///                        latest value from `self`. The result would be forwarded,
	///                        and would be used in the next call of `nextPartialResult`.
	///
	/// - returns: A signal that sends the partial results of the accumuation, and the
	///            final result as `self` completes.
	public func scan<U>(into initialResult: U, _ nextPartialResult: @escaping (inout U, Value) -> Void) -> Signal<U, Error> {
		return Signal<U, Error> { observer in
			var accumulator = initialResult

			return self.observe { event in
				observer.action(event.map { value in
					nextPartialResult(&accumulator, value)
					return accumulator
				})
			}
		}
	}
}

extension Signal where Value: Equatable {
	/// Forward only values from `self` that are not equal to its immediately preceding
	/// value.
	///
	/// - note: The first value is always forwarded.
	///
	/// - returns: A signal which conditionally forwards values from `self`.
	public func skipRepeats() -> Signal<Value, Error> {
		return skipRepeats(==)
	}
}

extension Signal {
	/// Forward only values from `self` that are not considered equivalent to its
	/// immediately preceding value.
	///
	/// - note: The first value is always forwarded.
	///
	/// - parameters:
	///   - isEquivalent: A closure to determine whether two values are equivalent.
	///
	/// - returns: A signal which conditionally forwards values from `self`.
	public func skipRepeats(_ isEquivalent: @escaping (Value, Value) -> Bool) -> Signal<Value, Error> {
		return self
			.scan((nil, false)) { (accumulated: (Value?, Bool), next: Value) -> (value: Value?, repeated: Bool) in
				switch accumulated.0 {
				case nil:
					return (next, false)
				case let prev? where isEquivalent(prev, next):
					return (prev, true)
				case _?:
					return (Optional(next), false)
				}
			}
			.filter { !$0.repeated }
			.filterMap { $0.value }
	}

	/// Do not forward any value from `self` until `shouldContinue` returns `false`, at
	/// which point the returned signal starts to forward values from `self`, including
	/// the one leading to the toggling.
	///
	/// - parameters:
	///   - shouldContinue: A closure to determine whether the skipping should continue.
	///
	/// - returns: A signal which conditionally forwards values from `self`.
	public func skip(while shouldContinue: @escaping (Value) -> Bool) -> Signal<Value, Error> {
		return Signal { observer in
			var isSkipping = true

			return self.observe { event in
				switch event {
				case let .value(value):
					isSkipping = isSkipping && shouldContinue(value)
					if !isSkipping {
						fallthrough
					}

				case .failed, .completed, .interrupted:
					observer.action(event)
				}
			}
		}
	}

	/// Forward events from `self` until `replacement` begins sending events.
	///
	/// - parameters:
	///   - replacement: A signal to wait to wait for values from and start
	///                  sending them as a replacement to `self`'s values.
	///
	/// - returns: A signal which passes through `value`, failed, and
	///            `interrupted` events from `self` until `replacement` sends
	///            an event, at which point the returned signal will send that
	///            event and switch to passing through events from `replacement`
	///            instead, regardless of whether `self` has sent events
	///            already.
	public func take(untilReplacement signal: Signal<Value, Error>) -> Signal<Value, Error> {
		return Signal { observer in
			let disposable = CompositeDisposable()

			let signalDisposable = self.observe { event in
				switch event {
				case .completed:
					break

				case .value, .failed, .interrupted:
					observer.action(event)
				}
			}

			disposable += signalDisposable
			disposable += signal.observe { event in
				signalDisposable?.dispose()
				observer.action(event)
			}

			return disposable
		}
	}

	/// Wait until `self` completes and then forward the final `count` values
	/// on the returned signal.
	///
	/// - parameters:
	///   - count: Number of last events to send after `self` completes.
	///
	/// - returns: A signal that receives up to `count` values from `self`
	///            after `self` completes.
	public func take(last count: Int) -> Signal<Value, Error> {
		return Signal { observer in
			var buffer: [Value] = []
			buffer.reserveCapacity(count)

			return self.observe { event in
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
					observer.send(error: error)
				case .completed:
					buffer.forEach(observer.send(value:))

					observer.sendCompleted()
				case .interrupted:
					observer.sendInterrupted()
				}
			}
		}
	}

	/// Forward any values from `self` until `shouldContinue` returns `false`, at which
	/// point the returned signal would complete.
	///
	/// - parameters:
	///   - shouldContinue: A closure to determine whether the forwarding of values should
	///                     continue.
	///
	/// - returns: A signal which conditionally forwards values from `self`.
	public func take(while shouldContinue: @escaping (Value) -> Bool) -> Signal<Value, Error> {
		return Signal { observer in
			return self.observe { event in
				if let value = event.value, !shouldContinue(value) {
					observer.sendCompleted()
				} else {
					observer.action(event)
				}
			}
		}
	}
}

extension Signal {
	/// Zip elements of two signals into pairs. The elements of any Nth pair
	/// are the Nth elements of the two input signals.
	///
	/// - parameters:
	///   - otherSignal: A signal to zip values with.
	///
	/// - returns: A signal that sends tuples of `self` and `otherSignal`.
	public func zip<U>(with other: Signal<U, Error>) -> Signal<(Value, U), Error> {
		return Signal.zip(self, other)
	}

	/// Forward the latest value on `scheduler` after at least `interval`
	/// seconds have passed since *the returned signal* last sent a value.
	///
	/// If `self` always sends values more frequently than `interval` seconds,
	/// then the returned signal will send a value every `interval` seconds.
	///
	/// To measure from when `self` last sent a value, see `debounce`.
	///
	/// - seealso: `debounce`
	///
	/// - note: If multiple values are received before the interval has elapsed,
	///         the latest value is the one that will be passed on.
	///
	/// - note: If `self` terminates while a value is being throttled, that
	///         value will be discarded and the returned signal will terminate
	///         immediately.
	///
	/// - note: If the device time changed backwards before previous date while
	///         a value is being throttled, and if there is a new value sent,
	///         the new value will be passed anyway.
	///
	/// - precondition: `interval` must be non-negative number.
	///
	/// - parameters:
	///   - interval: Number of seconds to wait between sent values.
	///   - scheduler: A scheduler to deliver events on.
	///
	/// - returns: A signal that sends values at least `interval` seconds
	///            appart on a given scheduler.
	public func throttle(_ interval: TimeInterval, on scheduler: DateScheduler) -> Signal<Value, Error> {
		precondition(interval >= 0)

		return Signal { observer in
			let state: Atomic<ThrottleState<Value>> = Atomic(ThrottleState())
			let schedulerDisposable = SerialDisposable()

			let disposable = CompositeDisposable()
			disposable += schedulerDisposable

			disposable += self.observe { event in
				guard let value = event.value else {
					schedulerDisposable.inner = scheduler.schedule {
						observer.action(event)
					}
					return
				}

				var scheduleDate: Date!
				state.modify {
					$0.pendingValue = value

					let proposedScheduleDate: Date
					if let previousDate = $0.previousDate, previousDate.compare(scheduler.currentDate) != .orderedDescending {
						proposedScheduleDate = previousDate.addingTimeInterval(interval)
					} else {
						proposedScheduleDate = scheduler.currentDate
					}

					switch proposedScheduleDate.compare(scheduler.currentDate) {
					case .orderedAscending:
						scheduleDate = scheduler.currentDate

					case .orderedSame: fallthrough
					case .orderedDescending:
						scheduleDate = proposedScheduleDate
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
						observer.send(value: pendingValue)
					}
				}
			}

			return disposable
		}
	}

	/// Conditionally throttles values sent on the receiver whenever
	/// `shouldThrottle` is true, forwarding values on the given scheduler.
	///
	/// - note: While `shouldThrottle` remains false, values are forwarded on the
	///         given scheduler. If multiple values are received while
	///         `shouldThrottle` is true, the latest value is the one that will
	///         be passed on.
	///
	/// - note: If the input signal terminates while a value is being throttled,
	///         that value will be discarded and the returned signal will
	///         terminate immediately.
	///
	/// - note: If `shouldThrottle` completes before the receiver, and its last
	///         value is `true`, the returned signal will remain in the throttled
	///         state, emitting no further values until it terminates.
	///
	/// - parameters:
	///   - shouldThrottle: A boolean property that controls whether values
	///                     should be throttled.
	///   - scheduler: A scheduler to deliver events on.
	///
	/// - returns: A signal that sends values only while `shouldThrottle` is false.
	public func throttle<P: PropertyProtocol>(while shouldThrottle: P, on scheduler: Scheduler) -> Signal<Value, Error>
		where P.Value == Bool
	{
		return Signal { observer in
			let initial: ThrottleWhileState<Value> = .resumed
			let state = Atomic(initial)
			let schedulerDisposable = SerialDisposable()

			let disposable = CompositeDisposable()
			disposable += schedulerDisposable

			disposable += shouldThrottle.producer
				.skipRepeats()
				.startWithValues { shouldThrottle in
					let valueToSend = state.modify { state -> Value? in
						guard !state.isTerminated else { return nil }

						if shouldThrottle {
							state = .throttled(nil)
						} else {
							defer { state = .resumed }

							if case let .throttled(value?) = state {
								return value
							}
						}

						return nil
					}

					if let value = valueToSend {
						schedulerDisposable.inner = scheduler.schedule {
							observer.send(value: value)
						}
					}
			}

			disposable += self.observe { event in
				let eventToSend = state.modify { state -> Event? in
					switch event {
					case let .value(value):
						switch state {
						case .throttled:
							state = .throttled(value)
							return nil
						case .resumed:
							return event
						case .terminated:
							return nil
						}

					case .completed, .interrupted, .failed:
						state = .terminated
						return event
					}
				}

				if let event = eventToSend {
					schedulerDisposable.inner = scheduler.schedule {
						observer.action(event)
					}
				}
			}

			return disposable
		}
	}

	/// Forward the latest value on `scheduler` after at least `interval`
	/// seconds have passed since `self` last sent a value.
	///
	/// If `self` always sends values more frequently than `interval` seconds,
	/// then the returned signal will never send any values.
	///
	/// To measure from when the *returned signal* last sent a value, see
	/// `throttle`.
	///
	/// - seealso: `throttle`
	///
	/// - note: If multiple values are received before the interval has elapsed,
	///         the latest value is the one that will be passed on.
	///
	/// - note: If the input signal terminates while a value is being debounced,
	///         that value will be discarded and the returned signal will
	///         terminate immediately.
	///
	/// - precondition: `interval` must be non-negative number.
	///
	/// - parameters:
	///   - interval: A number of seconds to wait before sending a value.
	///   - scheduler: A scheduler to send values on.
	///
	/// - returns: A signal that sends values that are sent from `self` at least
	///            `interval` seconds apart.
	public func debounce(_ interval: TimeInterval, on scheduler: DateScheduler) -> Signal<Value, Error> {
		precondition(interval >= 0)

		let d = SerialDisposable()

		return Signal { observer in
			return self.observe { event in
				switch event {
				case let .value(value):
					let date = scheduler.currentDate.addingTimeInterval(interval)
					d.inner = scheduler.schedule(after: date) {
						observer.send(value: value)
					}

				case .completed, .failed, .interrupted:
					d.inner = scheduler.schedule {
						observer.action(event)
					}
				}
			}
		}
	}
}

extension Signal {
	/// Forward only those values from `self` that have unique identities across
	/// the set of all values that have been seen.
	///
	/// - note: This causes the identities to be retained to check for
	///         uniqueness.
	///
	/// - parameters:
	///   - transform: A closure that accepts a value and returns identity
	///                value.
	///
	/// - returns: A signal that sends unique values during its lifetime.
	public func uniqueValues<Identity: Hashable>(_ transform: @escaping (Value) -> Identity) -> Signal<Value, Error> {
		return Signal { observer in
			var seenValues: Set<Identity> = []

			return self
				.observe { event in
					switch event {
					case let .value(value):
						let identity = transform(value)
						if !seenValues.contains(identity) {
							seenValues.insert(identity)
							fallthrough
						}

					case .failed, .completed, .interrupted:
						observer.action(event)
					}
			}
		}
	}
}

extension Signal where Value: Hashable {
	/// Forward only those values from `self` that are unique across the set of
	/// all values that have been seen.
	///
	/// - note: This causes the values to be retained to check for uniqueness.
	///         Providing a function that returns a unique value for each sent
	///         value can help you reduce the memory footprint.
	///
	/// - returns: A signal that sends unique values during its lifetime.
	public func uniqueValues() -> Signal<Value, Error> {
		return uniqueValues { $0 }
	}
}

private struct ThrottleState<Value> {
	var previousDate: Date? = nil
	var pendingValue: Value? = nil
}

private enum ThrottleWhileState<Value> {
	case resumed
	case throttled(Value?)
	case terminated

	var isTerminated: Bool {
		switch self {
		case .terminated:
			return true
		case .resumed, .throttled:
			return false
		}
	}
}

private protocol SignalAggregateStrategy {
	/// Update the latest value of the signal at `position` to be `value`.
	///
	/// - parameters:
	///   - value: The latest value emitted by the signal at `position`.
	///   - position: The position of the signal.
	///
	/// - returns: `true` if the aggregating signal should terminate as a result of the
	///            update. `false` otherwise.
	mutating func update(_ value: Any, at position: Int) -> Bool

	/// Record the completion of the signal at `position`.
	///
	/// - parameters:
	///   - position: The position of the signal.
	///
	/// - returns: `true` if the aggregating signal should terminate as a result of the
	///            completion. `false` otherwise.
	mutating func complete(at position: Int) -> Bool

	init(count: Int, action: @escaping (ContiguousArray<Any>) -> Void)
}

extension Signal {
	private struct CombineLatestStrategy: SignalAggregateStrategy {
		private enum Placeholder {
			case none
		}

		private var values: ContiguousArray<Any>
		private var completionCount: Int
		private let action: (ContiguousArray<Any>) -> Void

		private var _haveAllSentInitial: Bool
		private var haveAllSentInitial: Bool {
			mutating get {
				if _haveAllSentInitial {
					return true
				}

				_haveAllSentInitial = values.reduce(true) { $0 && !($1 is Placeholder) }
				return _haveAllSentInitial
			}
		}

		mutating func update(_ value: Any, at position: Int) -> Bool {
			values[position] = value

			if haveAllSentInitial {
				action(values)
			}

			return false
		}

		mutating func complete(at position: Int) -> Bool {
			completionCount += 1
			return completionCount == values.count
		}

		init(count: Int, action: @escaping (ContiguousArray<Any>) -> Void) {
			values = ContiguousArray(repeating: Placeholder.none, count: count)
			completionCount = 0
			_haveAllSentInitial = false
			self.action = action
		}
	}

	private struct ZipStrategy: SignalAggregateStrategy {
		private var values: ContiguousArray<[Any]>
		private var isCompleted: ContiguousArray<Bool>
		private let action: (ContiguousArray<Any>) -> Void

		private var hasCompletedAndEmptiedSignal: Bool {
			return Swift.zip(values, isCompleted).contains(where: { $0.isEmpty && $1 })
		}

		private var canEmit: Bool {
			return values.reduce(true) { $0 && !$1.isEmpty }
		}

		private var areAllCompleted: Bool {
			return isCompleted.reduce(true) { $0 && $1 }
		}

		mutating func update(_ value: Any, at position: Int) -> Bool {
			values[position].append(value)

			if canEmit {
				var buffer = ContiguousArray<Any>()
				buffer.reserveCapacity(values.count)

				for index in values.startIndex ..< values.endIndex {
					buffer.append(values[index].removeFirst())
				}

				action(buffer)

				if hasCompletedAndEmptiedSignal {
					return true
				}
			}

			return false
		}

		mutating func complete(at position: Int) -> Bool {
			isCompleted[position] = true

			// `zip` completes when all signals has completed, or any of the signals
			// has completed without any buffered value.
			return hasCompletedAndEmptiedSignal || areAllCompleted
		}

		init(count: Int, action: @escaping (ContiguousArray<Any>) -> Void) {
			values = ContiguousArray(repeating: [], count: count)
			isCompleted = ContiguousArray(repeating: false, count: count)
			self.action = action
		}
	}

	private final class AggregateBuilder<Strategy: SignalAggregateStrategy> {
		fileprivate var startHandlers: [(_ index: Int, _ strategy: Atomic<Strategy>, _ action: @escaping (Signal<Never, Error>.Event) -> Void) -> Disposable?]

		init() {
			self.startHandlers = []
		}

		@discardableResult
		func add<U>(_ signal: Signal<U, Error>) -> Self {
			startHandlers.append { index, strategy, action in
				return signal.observe { event in
					switch event {
					case let .value(value):
						let shouldComplete = strategy.modify {
							return $0.update(value, at: index)
						}

						if shouldComplete {
							action(.completed)
						}

					case .completed:
						let shouldComplete = strategy.modify {
							return $0.complete(at: index)
						}

						if shouldComplete {
							action(.completed)
						}

					case .interrupted:
						action(.interrupted)

					case let .failed(error):
						action(.failed(error))
					}
				}
			}

			return self
		}
	}

	private convenience init<Strategy>(_ builder: AggregateBuilder<Strategy>, _ transform: @escaping (ContiguousArray<Any>) -> Value) where Strategy: SignalAggregateStrategy {
		self.init { observer in
			let disposables = CompositeDisposable()
			let strategy = Atomic(Strategy(count: builder.startHandlers.count) { observer.send(value: transform($0)) })

			for (index, action) in builder.startHandlers.enumerated() where !disposables.isDisposed {
				disposables += action(index, strategy) { observer.action($0.map { _ in fatalError() }) }
			}

			return ActionDisposable {
				strategy.modify { _ in
					disposables.dispose()
				}
			}
		}
	}

	private convenience init<Strategy, U, S: Sequence>(_ strategy: Strategy.Type, _ signals: S) where Value == [U], Strategy: SignalAggregateStrategy, S.Iterator.Element == Signal<U, Error> {
		self.init(signals.reduce(AggregateBuilder<Strategy>()) { $0.add($1) }) { $0.map { $0 as! U } }
	}

	private convenience init<Strategy, A, B>(_ strategy: Strategy.Type, _ a: Signal<A, Error>, _ b: Signal<B, Error>) where Value == (A, B), Strategy: SignalAggregateStrategy {
		self.init(AggregateBuilder<Strategy>().add(a).add(b)) {
			return ($0[0] as! A, $0[1] as! B)
		}
	}

	private convenience init<Strategy, A, B, C>(_ strategy: Strategy.Type, _ a: Signal<A, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>) where Value == (A, B, C), Strategy: SignalAggregateStrategy {
		self.init(AggregateBuilder<Strategy>().add(a).add(b).add(c)) {
			return ($0[0] as! A, $0[1] as! B, $0[2] as! C)
		}
	}

	private convenience init<Strategy, A, B, C, D>(_ strategy: Strategy.Type, _ a: Signal<A, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>) where Value == (A, B, C, D), Strategy: SignalAggregateStrategy {
		self.init(AggregateBuilder<Strategy>().add(a).add(b).add(c).add(d)) {
			return ($0[0] as! A, $0[1] as! B, $0[2] as! C, $0[3] as! D)
		}
	}

	private convenience init<Strategy, A, B, C, D, E>(_ strategy: Strategy.Type, _ a: Signal<A, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>) where Value == (A, B, C, D, E), Strategy: SignalAggregateStrategy {
		self.init(AggregateBuilder<Strategy>().add(a).add(b).add(c).add(d).add(e)) {
			return ($0[0] as! A, $0[1] as! B, $0[2] as! C, $0[3] as! D, $0[4] as! E)
		}
	}

	private convenience init<Strategy, A, B, C, D, E, F>(_ strategy: Strategy.Type, _ a: Signal<A, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>) where Value == (A, B, C, D, E, F), Strategy: SignalAggregateStrategy {
		self.init(AggregateBuilder<Strategy>().add(a).add(b).add(c).add(d).add(e).add(f)) {
			return ($0[0] as! A, $0[1] as! B, $0[2] as! C, $0[3] as! D, $0[4] as! E, $0[5] as! F)
		}
	}

	private convenience init<Strategy, A, B, C, D, E, F, G>(_ strategy: Strategy.Type, _ a: Signal<A, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>) where Value == (A, B, C, D, E, F, G), Strategy: SignalAggregateStrategy {
		self.init(AggregateBuilder<Strategy>().add(a).add(b).add(c).add(d).add(e).add(f).add(g)) {
			return ($0[0] as! A, $0[1] as! B, $0[2] as! C, $0[3] as! D, $0[4] as! E, $0[5] as! F, $0[6] as! G)
		}
	}

	private convenience init<Strategy, A, B, C, D, E, F, G, H>(_ strategy: Strategy.Type, _ a: Signal<A, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>, _ h: Signal<H, Error>) where Value == (A, B, C, D, E, F, G, H), Strategy: SignalAggregateStrategy {
		self.init(AggregateBuilder<Strategy>().add(a).add(b).add(c).add(d).add(e).add(f).add(g).add(h)) {
			return ($0[0] as! A, $0[1] as! B, $0[2] as! C, $0[3] as! D, $0[4] as! E, $0[5] as! F, $0[6] as! G, $0[7] as! H)
		}
	}

	private convenience init<Strategy, A, B, C, D, E, F, G, H, I>(_ strategy: Strategy.Type, _ a: Signal<A, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>, _ h: Signal<H, Error>, _ i: Signal<I, Error>) where Value == (A, B, C, D, E, F, G, H, I), Strategy: SignalAggregateStrategy {
		self.init(AggregateBuilder<Strategy>().add(a).add(b).add(c).add(d).add(e).add(f).add(g).add(h).add(i)) {
			return ($0[0] as! A, $0[1] as! B, $0[2] as! C, $0[3] as! D, $0[4] as! E, $0[5] as! F, $0[6] as! G, $0[7] as! H, $0[8] as! I)
		}
	}

	private convenience init<Strategy, A, B, C, D, E, F, G, H, I, J>(_ strategy: Strategy.Type, _ a: Signal<A, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>, _ h: Signal<H, Error>, _ i: Signal<I, Error>, _ j: Signal<J, Error>) where Value == (A, B, C, D, E, F, G, H, I, J), Strategy: SignalAggregateStrategy {
		self.init(AggregateBuilder<Strategy>().add(a).add(b).add(c).add(d).add(e).add(f).add(g).add(h).add(i).add(j)) {
			return ($0[0] as! A, $0[1] as! B, $0[2] as! C, $0[3] as! D, $0[4] as! E, $0[5] as! F, $0[6] as! G, $0[7] as! H, $0[8] as! I, $0[9] as! J)
		}
	}

	/// Combines the values of all the given signals, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>) -> Signal<(Value, B), Error> {
		return .init(CombineLatestStrategy.self, a, b)
	}

	/// Combines the values of all the given signals, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>) -> Signal<(Value, B, C), Error> {
		return .init(CombineLatestStrategy.self, a, b, c)
	}

	/// Combines the values of all the given signals, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>) -> Signal<(Value, B, C, D), Error> {
		return .init(CombineLatestStrategy.self, a, b, c, d)
	}

	/// Combines the values of all the given signals, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D, E>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>) -> Signal<(Value, B, C, D, E), Error> {
		return .init(CombineLatestStrategy.self, a, b, c, d, e)
	}

	/// Combines the values of all the given signals, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D, E, F>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>) -> Signal<(Value, B, C, D, E, F), Error> {
		return .init(CombineLatestStrategy.self, a, b, c, d, e, f)
	}

	/// Combines the values of all the given signals, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D, E, F, G>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>) -> Signal<(Value, B, C, D, E, F, G), Error> {
		return .init(CombineLatestStrategy.self, a, b, c, d, e, f, g)
	}

	/// Combines the values of all the given signals, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D, E, F, G, H>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>, _ h: Signal<H, Error>) -> Signal<(Value, B, C, D, E, F, G, H), Error> {
		return .init(CombineLatestStrategy.self, a, b, c, d, e, f, g, h)
	}

	/// Combines the values of all the given signals, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D, E, F, G, H, I>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>, _ h: Signal<H, Error>, _ i: Signal<I, Error>) -> Signal<(Value, B, C, D, E, F, G, H, I), Error> {
		return .init(CombineLatestStrategy.self, a, b, c, d, e, f, g, h, i)
	}

	/// Combines the values of all the given signals, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D, E, F, G, H, I, J>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>, _ h: Signal<H, Error>, _ i: Signal<I, Error>, _ j: Signal<J, Error>) -> Signal<(Value, B, C, D, E, F, G, H, I, J), Error> {
		return .init(CombineLatestStrategy.self, a, b, c, d, e, f, g, h, i, j)
	}

	/// Combines the values of all the given signals, in the manner described by
	/// `combineLatest(with:)`. No events will be sent if the sequence is empty.
	public static func combineLatest<S: Sequence>(_ signals: S) -> Signal<[Value], Error> where S.Iterator.Element == Signal<Value, Error> {
		return .init(CombineLatestStrategy.self, signals)
	}

	/// Zip the values of all the given signals, in the manner described by `zip(with:)`.
	public static func zip<B>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>) -> Signal<(Value, B), Error> {
		return .init(ZipStrategy.self, a, b)
	}

	/// Zip the values of all the given signals, in the manner described by `zip(with:)`.
	public static func zip<B, C>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>) -> Signal<(Value, B, C), Error> {
		return .init(ZipStrategy.self, a, b, c)
	}

	/// Zip the values of all the given signals, in the manner described by `zip(with:)`.
	public static func zip<B, C, D>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>) -> Signal<(Value, B, C, D), Error> {
		return .init(ZipStrategy.self, a, b, c, d)
	}

	/// Zip the values of all the given signals, in the manner described by `zip(with:)`.
	public static func zip<B, C, D, E>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>) -> Signal<(Value, B, C, D, E), Error> {
		return .init(ZipStrategy.self, a, b, c, d, e)
	}

	/// Zip the values of all the given signals, in the manner described by `zip(with:)`.
	public static func zip<B, C, D, E, F>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>) -> Signal<(Value, B, C, D, E, F), Error> {
		return .init(ZipStrategy.self, a, b, c, d, e, f)
	}

	/// Zip the values of all the given signals, in the manner described by `zip(with:)`.
	public static func zip<B, C, D, E, F, G>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>) -> Signal<(Value, B, C, D, E, F, G), Error> {
		return .init(ZipStrategy.self, a, b, c, d, e, f, g)
	}

	/// Zip the values of all the given signals, in the manner described by `zip(with:)`.
	public static func zip<B, C, D, E, F, G, H>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>, _ h: Signal<H, Error>) -> Signal<(Value, B, C, D, E, F, G, H), Error> {
		return .init(ZipStrategy.self, a, b, c, d, e, f, g, h)
	}

	/// Zip the values of all the given signals, in the manner described by `zip(with:)`.
	public static func zip<B, C, D, E, F, G, H, I>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>, _ h: Signal<H, Error>, _ i: Signal<I, Error>) -> Signal<(Value, B, C, D, E, F, G, H, I), Error> {
		return .init(ZipStrategy.self, a, b, c, d, e, f, g, h, i)
	}

	/// Zip the values of all the given signals, in the manner described by `zip(with:)`.
	public static func zip<B, C, D, E, F, G, H, I, J>(_ a: Signal<Value, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>, _ h: Signal<H, Error>, _ i: Signal<I, Error>, _ j: Signal<J, Error>) -> Signal<(Value, B, C, D, E, F, G, H, I, J), Error> {
		return .init(ZipStrategy.self, a, b, c, d, e, f, g, h, i, j)
	}

	/// Zips the values of all the given signals, in the manner described by
	/// `zip(with:)`. No events will be sent if the sequence is empty.
	public static func zip<S: Sequence>(_ signals: S) -> Signal<[Value], Error> where S.Iterator.Element == Signal<Value, Error> {
		return .init(ZipStrategy.self, signals)
	}
}

extension Signal {
	/// Forward events from `self` until `interval`. Then if signal isn't
	/// completed yet, fails with `error` on `scheduler`.
	///
	/// - note: If the interval is 0, the timeout will be scheduled immediately.
	///         The signal must complete synchronously (or on a faster
	///         scheduler) to avoid the timeout.
	///
	/// - precondition: `interval` must be non-negative number.
	///
	/// - parameters:
	///   - error: Error to send with failed event if `self` is not completed
	///            when `interval` passes.
	///   - interval: Number of seconds to wait for `self` to complete.
	///   - scheudler: A scheduler to deliver error on.
	///
	/// - returns: A signal that sends events for at most `interval` seconds,
	///            then, if not `completed` - sends `error` with failed event
	///            on `scheduler`.
	public func timeout(after interval: TimeInterval, raising error: Error, on scheduler: DateScheduler) -> Signal<Value, Error> {
		precondition(interval >= 0)

		return Signal { observer in
			let disposable = CompositeDisposable()
			let date = scheduler.currentDate.addingTimeInterval(interval)

			disposable += scheduler.schedule(after: date) {
				observer.send(error: error)
			}

			disposable += self.observe(observer)
			return disposable
		}
	}
}

extension Signal where Error == NoError {
	/// Promote a signal that does not generate failures into one that can.
	///
	/// - note: This does not actually cause failures to be generated for the
	///         given signal, but makes it easier to combine with other signals
	///         that may fail; for example, with operators like
	///         `combineLatestWith`, `zipWith`, `flatten`, etc.
	///
	/// - parameters:
	///   - _ An `ErrorType`.
	///
	/// - returns: A signal that has an instantiatable `ErrorType`.
	public func promoteErrors<F: Swift.Error>(_: F.Type) -> Signal<Value, F> {
		return Signal<Value, F> { observer in
			return self.observe { event in
				switch event {
				case let .value(value):
					observer.send(value: value)
				case .failed:
					fatalError("NoError is impossible to construct")
				case .completed:
					observer.sendCompleted()
				case .interrupted:
					observer.sendInterrupted()
				}
			}
		}
	}

	/// Forward events from `self` until `interval`. Then if signal isn't
	/// completed yet, fails with `error` on `scheduler`.
	///
	/// - note: If the interval is 0, the timeout will be scheduled immediately.
	///         The signal must complete synchronously (or on a faster
	///         scheduler) to avoid the timeout.
	///
	/// - parameters:
	///   - interval: Number of seconds to wait for `self` to complete.
	///   - error: Error to send with `failed` event if `self` is not completed
	///            when `interval` passes.
	///   - scheudler: A scheduler to deliver error on.
	///
	/// - returns: A signal that sends events for at most `interval` seconds,
	///            then, if not `completed` - sends `error` with `failed` event
	///            on `scheduler`.
	public func timeout<NewError: Swift.Error>(
		after interval: TimeInterval,
		raising error: NewError,
		on scheduler: DateScheduler
		) -> Signal<Value, NewError> {
		return self
			.promoteErrors(NewError.self)
			.timeout(after: interval, raising: error, on: scheduler)
	}
}

extension Signal where Value == Bool {
	/// Create a signal that computes a logical NOT in the latest values of `self`.
	///
	/// - returns: A signal that emits the logical NOT results.
	public func negate() -> Signal<Value, Error> {
		return self.map(!)
	}

	/// Create a signal that computes a logical AND between the latest values of `self`
	/// and `signal`.
	///
	/// - parameters:
	///   - signal: Signal to be combined with `self`.
	///
	/// - returns: A signal that emits the logical AND results.
	public func and(_ signal: Signal<Value, Error>) -> Signal<Value, Error> {
		return self.combineLatest(with: signal).map { $0 && $1 }
	}

	/// Create a signal that computes a logical OR between the latest values of `self`
	/// and `signal`.
	///
	/// - parameters:
	///   - signal: Signal to be combined with `self`.
	///
	/// - returns: A signal that emits the logical OR results.
	public func or(_ signal: Signal<Value, Error>) -> Signal<Value, Error> {
		return self.combineLatest(with: signal).map { $0 || $1 }
	}
}

extension Signal {
	/// Apply an action to every value from `self`, and forward the value if the action
	/// succeeds. If the action fails with an error, the returned `Signal` would propagate
	/// the failure and terminate.
	///
	/// - parameters:
	///   - action: An action which yields a `Result`.
	///
	/// - returns: A signal which forwards the values from `self` until the given action
	///            fails.
	public func attempt(_ action: @escaping (Value) -> Result<(), Error>) -> Signal<Value, Error> {
		return attemptMap { value in
			return action(value).map {
				return value
			}
		}
	}

	/// Apply a transform to every value from `self`, and forward the transformed value
	/// if the action succeeds. If the action fails with an error, the returned `Signal`
	/// would propagate the failure and terminate.
	///
	/// - parameters:
	///   - action: A transform which yields a `Result` of the transformed value or the
	///             error.
	///
	/// - returns: A signal which forwards the transformed values.
	public func attemptMap<U>(_ transform: @escaping (Value) -> Result<U, Error>) -> Signal<U, Error> {
		return Signal<U, Error> { observer in
			self.observe { event in
				switch event {
				case let .value(value):
					transform(value).analysis(
						ifSuccess: observer.send(value:),
						ifFailure: observer.send(error:)
					)
				case let .failed(error):
					observer.send(error: error)
				case .completed:
					observer.sendCompleted()
				case .interrupted:
					observer.sendInterrupted()
				}
			}
		}
	}
}

extension Signal where Error == NoError {
	/// Apply a throwable action to every value from `self`, and forward the values
	/// if the action succeeds. If the action throws an error, the returned `Signal`
	/// would propagate the failure and terminate.
	///
	/// - parameters:
	///   - action: A throwable closure to perform an arbitrary action on the value.
	///
	/// - returns: A signal which forwards the successful values of the given action.
	public func attempt(_ action: @escaping (Value) throws -> Void) -> Signal<Value, AnyError> {
		return self
			.promoteErrors(AnyError.self)
			.attempt(action)
	}

	/// Apply a throwable transform to every value from `self`, and forward the results
	/// if the action succeeds. If the transform throws an error, the returned `Signal`
	/// would propagate the failure and terminate.
	///
	/// - parameters:
	///   - transform: A throwable transform.
	///
	/// - returns: A signal which forwards the successfully transformed values.
	public func attemptMap<U>(_ transform: @escaping (Value) throws -> U) -> Signal<U, AnyError> {
		return self
			.promoteErrors(AnyError.self)
			.attemptMap(transform)
	}
}

extension Signal where Error == AnyError {
	/// Apply a throwable action to every value from `self`, and forward the values
	/// if the action succeeds. If the action throws an error, the returned `Signal`
	/// would propagate the failure and terminate.
	///
	/// - parameters:
	///   - action: A throwable closure to perform an arbitrary action on the value.
	///
	/// - returns: A signal which forwards the successful values of the given action.
	public func attempt(_ action: @escaping (Value) throws -> Void) -> Signal<Value, AnyError> {
		return attemptMap { value in
			try action(value)
			return value
		}
	}

	/// Apply a throwable transform to every value from `self`, and forward the results
	/// if the action succeeds. If the transform throws an error, the returned `Signal`
	/// would propagate the failure and terminate.
	///
	/// - parameters:
	///   - transform: A throwable transform.
	///
	/// - returns: A signal which forwards the successfully transformed values.
	public func attemptMap<U>(_ transform: @escaping (Value) throws -> U) -> Signal<U, AnyError> {
		return attemptMap { value in
			ReactiveSwift.materialize {
				try transform(value)
			}
		}
	}
}
