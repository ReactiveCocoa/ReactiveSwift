import Foundation

/// Represents reactive primitives that can be represented by `SignalProducer`.
public protocol SignalProducerConvertible {
	/// The type of values being sent by `self`.
	associatedtype Value

	/// The type of error that can occur on `self`.
	associatedtype Error: Swift.Error

	/// The `SignalProducer` representation of `self`.
	var producer: SignalProducer<Value, Error> { get }
}

// MARK: - Any

extension SignalProducerConvertible {
	/// Create a `Signal` from `self`, pass it into the given closure, and start the
	/// associated work on the produced `Signal` as the closure returns.
	///
	/// - parameters:
	///   - setup: A closure to be invoked before the work associated with the produced
	///            `Signal` commences. Both the produced `Signal` and an interrupt handle
	///            of the signal would be passed to the closure.
	/// - returns: The return value of the given setup closure.
	@discardableResult
	func startWithSignal<Result>(
		_ setup: (_ signal: Signal<Value, Error>, _ interruptHandle: Disposable) -> Result
	) -> Result {
		producer.startWithSignal(setup)
	}
	
	/// Create a `Signal` from `self`, and observe it with the given observer.
	///
	/// - parameters:
	///   - observer: An observer to attach to the produced `Signal`.
	///
	/// - returns: A disposable to interrupt the produced `Signal`.
	@discardableResult
	public func start(_ observer: Signal<Value, Error>.Observer = .init()) -> Disposable {
		producer.start(observer)
	}

	/// Create a `Signal` from `self`, and observe the `Signal` for all events
	/// being emitted.
	///
	/// - parameters:
	///   - action: A closure to be invoked with every event from `self`.
	///
	/// - returns: A disposable to interrupt the produced `Signal`.
	@discardableResult
	public func start(_ action: @escaping Signal<Value, Error>.Observer.Action) -> Disposable {
		producer.start(action)
	}

	/// Create a `Signal` from `self`, and observe the `Signal` for all values being
	/// emitted, and if any, its failure.
	///
	/// - parameters:
	///   - action: A closure to be invoked with values from `self`, or the propagated
	///             error should any `failed` event is emitted.
	///
	/// - returns: A disposable to interrupt the produced `Signal`.
	@discardableResult
	public func startWithResult(_ action: @escaping (Result<Value, Error>) -> Void) -> Disposable {
		producer.startWithResult(action)
	}

	/// Create a `Signal` from `self`, and observe its completion.
	///
	/// - parameters:
	///   - action: A closure to be invoked when a `completed` event is emitted.
	///
	/// - returns: A disposable to interrupt the produced `Signal`.
	@discardableResult
	public func startWithCompleted(_ action: @escaping () -> Void) -> Disposable {
		producer.startWithCompleted(action)
	}

	/// Create a `Signal` from `self`, and observe its failure.
	///
	/// - parameters:
	///   - action: A closure to be invoked with the propagated error, should any
	///             `failed` event is emitted.
	///
	/// - returns: A disposable to interrupt the produced `Signal`.
	@discardableResult
	public func startWithFailed(_ action: @escaping (Error) -> Void) -> Disposable {
		producer.startWithFailed(action)
	}

	/// Create a `Signal` from `self`, and observe its interruption.
	///
	/// - parameters:
	///   - action: A closure to be invoked when an `interrupted` event is emitted.
	///
	/// - returns: A disposable to interrupt the produced `Signal`.
	@discardableResult
	public func startWithInterrupted(_ action: @escaping () -> Void) -> Disposable {
		producer.startWithInterrupted(action)
	}
	
	/// Lift an unary Signal operator to operate upon SignalProducers instead.
	///
	/// In other words, this will create a new `SignalProducer` which will apply
	/// the given `Signal` operator to _every_ created `Signal`, just as if the
	/// operator had been applied to each `Signal` yielded from `start()`.
	///
	/// - parameters:
	///   - transform: An unary operator to lift.
	///
	/// - returns: A signal producer that applies signal's operator to every
	///            created signal.
	public func lift<U, F>(
		_ transform: @escaping (Signal<Value, Error>) -> Signal<U, F>
	) -> SignalProducer<U, F> {
		producer.lift(transform)
	}
	
	/// Lift a binary Signal operator to operate upon SignalProducers instead.
	///
	/// In other words, this will create a new `SignalProducer` which will apply
	/// the given `Signal` operator to _every_ `Signal` created from the two
	/// producers, just as if the operator had been applied to each `Signal`
	/// yielded from `start()`.
	///
	/// - note: starting the returned producer will start the receiver of the
	///         operator, which may not be adviseable for some operators.
	///
	/// - parameters:
	///   - transform: A binary operator to lift.
	///
	/// - returns: A binary operator that operates on two signal producers.
	public func lift<U, F, V, G>(
		_ transform: @escaping (Signal<Value, Error>) -> (Signal<U, F>) -> Signal<V, G>
	) -> (SignalProducer<U, F>) -> SignalProducer<V, G> {
		producer.lift(transform)
	}
	
	/// Map each value in the producer to a new value.
	///
	/// - parameters:
	///   - transform: A closure that accepts a value and returns a different
	///                value.
	///
	/// - returns: A signal producer that, when started, will send a mapped
	///            value of `self.`
	public func map<U>(_ transform: @escaping (Value) -> U) -> SignalProducer<U, Error> {
		producer.map(transform)
	}
	
	/// Map each value in the producer to a new constant value.
	///
	/// - parameters:
	///   - value: A new value.
	///
	/// - returns: A signal producer that, when started, will send a mapped
	///            value of `self`.
	public func map<U>(value: U) -> SignalProducer<U, Error> {
		producer.map(value: value)
	}

	/// Map each value in the producer to a new value by applying a key path.
	///
	/// - parameters:
	///   - keyPath: A key path relative to the producer's `Value` type.
	///
	/// - returns: A producer that will send new values.
	public func map<U>(_ keyPath: KeyPath<Value, U>) -> SignalProducer<U, Error> {
		producer.map(keyPath)
	}

	/// Map errors in the producer to a new error.
	///
	/// - parameters:
	///   - transform: A closure that accepts an error object and returns a
	///                different error.
	///
	/// - returns: A producer that emits errors of new type.
	public func mapError<F>(_ transform: @escaping (Error) -> F) -> SignalProducer<Value, F> {
		producer.mapError(transform)
	}

	/// Maps each value in the producer to a new value, lazily evaluating the
	/// supplied transformation on the specified scheduler.
	///
	/// - important: Unlike `map`, there is not a 1-1 mapping between incoming
	///              values, and values sent on the returned producer. If
	///              `scheduler` has not yet scheduled `transform` for
	///              execution, then each new value will replace the last one as
	///              the parameter to `transform` once it is finally executed.
	///
	/// - parameters:
	///   - transform: The closure used to obtain the returned value from this
	///                producer's underlying value.
	///
	/// - returns: A producer that, when started, sends values obtained using
	///            `transform` as this producer sends values.
	public func lazyMap<U>(on scheduler: Scheduler, transform: @escaping (Value) -> U) -> SignalProducer<U, Error> {
		producer.lazyMap(on: scheduler, transform: transform)
	}

	/// Preserve only values which pass the given closure.
	///
	/// - parameters:
	///   - isIncluded: A closure to determine whether a value from `self` should be
	///                 included in the produced `Signal`.
	///
	/// - returns: A producer that, when started, forwards the values passing the given
	///            closure.
	public func filter(_ isIncluded: @escaping (Value) -> Bool) -> SignalProducer<Value, Error> {
		producer.filter(isIncluded)
	}

	/// Applies `transform` to values from the producer and forwards values with non `nil` results unwrapped.
	/// - parameters:
	///   - transform: A closure that accepts a value from the `value` event and
	///                returns a new optional value.
	///
	/// - returns: A producer that will send new values, that are non `nil` after the transformation.
	public func compactMap<U>(_ transform: @escaping (Value) -> U?) -> SignalProducer<U, Error> {
		producer.compactMap(transform)
	}

	/// Yield the first `count` values from the input producer.
	///
	/// - precondition: `count` must be non-negative number.
	///
	/// - parameters:
	///   - count: A number of values to take from the signal.
	///
	/// - returns: A producer that, when started, will yield the first `count`
	///            values from `self`.
	public func take(first count: Int) -> SignalProducer<Value, Error> {
		producer.take(first: count)
	}

	/// Yield an array of values when `self` completes.
	///
	/// - note: When `self` completes without collecting any value, it will send
	///         an empty array of values.
	///
	/// - returns: A producer that, when started, will yield an array of values
	///            when `self` completes.
	public func collect() -> SignalProducer<[Value], Error> {
		producer.collect()
	}

	/// Yield an array of values until it reaches a certain count.
	///
	/// - precondition: `count` must be greater than zero.
	///
	/// - note: When the count is reached the array is sent and the signal
	///         starts over yielding a new array of values.
	///
	/// - note: When `self` completes any remaining values will be sent, the
	///         last array may not have `count` values. Alternatively, if were
	///         not collected any values will sent an empty array of values.
	///
	/// - returns: A producer that, when started, collects at most `count`
	///            values from `self`, forwards them as a single array and
	///            completes.
	public func collect(count: Int) -> SignalProducer<[Value], Error> {
		producer.collect(count: count)
	}

	/// Collect values from `self`, and emit them if the predicate passes.
	///
	/// When `self` completes any remaining values will be sent, regardless of the
	/// collected values matching `shouldEmit` or not.
	///
	/// If `self` completes without having emitted any value, an empty array would be
	/// emitted, followed by the completion of the produced `Signal`.
	///
	/// ````
	/// let (producer, observer) = SignalProducer<Int, Never>.buffer(1)
	///
	/// producer
	///     .collect { values in values.reduce(0, combine: +) == 8 }
	///     .startWithValues { print($0) }
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
	///                 whether the collected values should be emitted.
	///
	/// - returns: A producer of arrays of values, as instructed by the `shouldEmit`
	///            closure.
	public func collect(_ shouldEmit: @escaping (_ values: [Value]) -> Bool) -> SignalProducer<[Value], Error> {
		producer.collect(shouldEmit)
	}

	/// Collect values from `self`, and emit them if the predicate passes.
	///
	/// When `self` completes any remaining values will be sent, regardless of the
	/// collected values matching `shouldEmit` or not.
	///
	/// If `self` completes without having emitted any value, an empty array would be
	/// emitted, followed by the completion of the produced `Signal`.
	///
	/// ````
	/// let (producer, observer) = SignalProducer<Int, Never>.buffer(1)
	///
	/// producer
	///     .collect { values, value in value == 7 }
	///     .startWithValues { print($0) }
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
	/// - returns: A producer of arrays of values, as instructed by the `shouldEmit`
	///            closure.
	public func collect(
		_ shouldEmit: @escaping (_ collected: [Value], _ latest: Value) -> Bool
	) -> SignalProducer<[Value], Error> {
		producer.collect(shouldEmit)
	}

	/// Forward the latest values on `scheduler` every `interval`.
	///
	/// - note: If `self` terminates while values are being accumulated,
	///         the behaviour will be determined by `discardWhenCompleted`.
	///         If `true`, the values will be discarded and the returned producer
	///         will terminate immediately.
	///         If `false`, that values will be delivered at the next interval.
	///
	/// - parameters:
	///   - interval: A repetition interval.
	///   - scheduler: A scheduler to send values on.
	///   - skipEmpty: Whether empty arrays should be sent if no values were
	///     accumulated during the interval.
	///   - discardWhenCompleted: A boolean to indicate if the latest unsent
	///     values should be discarded on completion.
	///
	/// - returns: A producer that sends all values that are sent from `self`
	///            at `interval` seconds apart.
	public func collect(
		every interval: DispatchTimeInterval,
		on scheduler: DateScheduler,
		skipEmpty: Bool = false,
		discardWhenCompleted: Bool = true
	) -> SignalProducer<[Value], Error> {
		producer.collect(
			every: interval,
			on: scheduler,
			skipEmpty: skipEmpty,
			discardWhenCompleted: discardWhenCompleted
		)
	}

	/// Forward all events onto the given scheduler, instead of whichever
	/// scheduler they originally arrived upon.
	///
	/// - parameters:
	///   - scheduler: A scheduler to deliver events on.
	///
	/// - returns: A producer that, when started, will yield `self` values on
	///            provided scheduler.
	public func observe(on scheduler: Scheduler) -> SignalProducer<Value, Error> {
		producer.observe(on: scheduler)
	}
	
	/// Combine the latest value of the receiver with the latest value from the
	/// given producer.
	///
	/// - note: The returned producer will not send a value until both inputs
	///         have sent at least one value each.
	///
	/// - note: If either producer is interrupted, the returned producer will
	///         also be interrupted.
	///
	/// - note: The returned producer will not complete until both inputs
	///         complete.
	///
	/// - parameters:
	///   - other: A producer to combine `self`'s value with.
	///
	/// - returns: A producer that, when started, will yield a tuple containing
	///            values of `self` and given producer.
	public func combineLatest<Other: SignalProducerConvertible>(
		with other: Other
	) -> SignalProducer<(Value, Other.Value), Error> where Other.Error == Error {
		producer.combineLatest(with: other)
	}

	/// Merge the given producer into a single `SignalProducer` that will emit all
	/// values from both of them, and complete when all of them have completed.
	///
	/// - parameters:
	///   - other: A producer to merge `self`'s value with.
	///
	/// - returns: A producer that sends all values of `self` and given producer.
	public func merge<Other: SignalProducerConvertible>(
		with other: Other
	) -> SignalProducer<Value, Error> where Other.Value == Value, Other.Error == Error {
		producer.merge(with: other)
	}

	/// Delay `value` and `completed` events by the given interval, forwarding
	/// them on the given scheduler.
	///
	/// - note: `failed` and `interrupted` events are always scheduled
	///         immediately.
	///
	/// - parameters:
	///   - interval: Interval to delay `value` and `completed` events by.
	///   - scheduler: A scheduler to deliver delayed events on.
	///
	/// - returns: A producer that, when started, will delay `value` and
	///            `completed` events and will yield them on given scheduler.
	public func delay(_ interval: TimeInterval, on scheduler: DateScheduler) -> SignalProducer<Value, Error> {
		producer.delay(interval, on: scheduler)
	}

	/// Skip the first `count` values, then forward everything afterward.
	///
	/// - parameters:
	///   - count: A number of values to skip.
	///
	/// - returns:  A producer that, when started, will skip the first `count`
	///             values, then forward everything afterward.
	public func skip(first count: Int) -> SignalProducer<Value, Error> {
		producer.skip(first: count)
	}

	/// Treats all Events from the input producer as plain values, allowing them
	/// to be manipulated just like any other value.
	///
	/// In other words, this brings Events “into the monad.”
	///
	/// - note: When a Completed or Failed event is received, the resulting
	///         producer will send the Event itself and then complete. When an
	///         `interrupted` event is received, the resulting producer will
	///         send the `Event` itself and then interrupt.
	///
	/// - returns: A producer that sends events as its values.
	public func materialize() -> SignalProducer<Signal<Value, Error>.Event, Never> {
		producer.materialize()
	}

	/// Treats all Results from the input producer as plain values, allowing them
	/// to be manipulated just like any other value.
	///
	/// In other words, this brings Results “into the monad.”
	///
	/// - note: When a Failed event is received, the resulting producer will
	///         send the `Result.failure` itself and then complete.
	///
	/// - returns: A producer that sends results as its values.
	public func materializeResults() -> SignalProducer<Result<Value, Error>, Never> {
		producer.materializeResults()
	}

	/// Forward the latest value from `self` with the value from `sampler` as a
	/// tuple, only when `sampler` sends a `value` event.
	///
	/// - note: If `sampler` fires before a value has been observed on `self`,
	///         nothing happens.
	///
	/// - parameters:
	///   - sampler: A producer that will trigger the delivery of `value` event
	///              from `self`.
	///
	/// - returns: A producer that will send values from `self` and `sampler`,
	///            sampled (possibly multiple times) by `sampler`, then complete
	///            once both input producers have completed, or interrupt if
	///            either input producer is interrupted.
	public func sample<Sampler: SignalProducerConvertible>(
		with sampler: Sampler
	) -> SignalProducer<(Value, Sampler.Value), Error> where Sampler.Error == Never {
		producer.sample(with: sampler)
	}

	/// Forward the latest value from `self` whenever `sampler` sends a `value`
	/// event.
	///
	/// - note: If `sampler` fires before a value has been observed on `self`,
	///         nothing happens.
	///
	/// - parameters:
	///   - sampler: A producer that will trigger the delivery of `value` event
	///              from `self`.
	///
	/// - returns: A producer that, when started, will send values from `self`,
	///            sampled (possibly multiple times) by `sampler`, then complete
	///            once both input producers have completed, or interrupt if
	///            either input producer is interrupted.
	public func sample<Sampler: SignalProducerConvertible>(
		on sampler: Sampler
	) -> SignalProducer<Value, Error> where Sampler.Value == (), Sampler.Error == Never {
		producer.sample(on: sampler)
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
	/// - returns: A producer that will send values from `self` and `samplee`,
	///            sampled (possibly multiple times) by `self`, then terminate
	///            once `self` has terminated. **`samplee`'s terminated events
	///            are ignored**.
	public func withLatest<Samplee: SignalProducerConvertible>(
		from samplee: Samplee
	) -> SignalProducer<(Value, Samplee.Value), Error> where Samplee.Error == Never {
		producer.withLatest(from: samplee)
	}

	/// Forwards events from `self` until `lifetime` ends, at which point the
	/// returned producer will complete.
	///
	/// - parameters:
	///   - lifetime: A lifetime whose `ended` signal will cause the returned
	///               producer to complete.
	///
	/// - returns: A producer that will deliver events until `lifetime` ends.
	public func take(during lifetime: Lifetime) -> SignalProducer<Value, Error> {
		producer.take(during: lifetime)
	}

	/// Forward events from `self` until `trigger` sends a `value` or `completed`
	/// event, at which point the returned producer will complete.
	///
	/// - parameters:
	///   - trigger: A producer whose `value` or `completed` events will stop the
	///              delivery of `value` events from `self`.
	///
	/// - returns: A producer that will deliver events until `trigger` sends
	///            `value` or `completed` events.
	public func take<Trigger: SignalProducerConvertible>(
		until trigger: Trigger
	) -> SignalProducer<Value, Error> where Trigger.Value == (), Trigger.Error == Never {
		producer.take(until: trigger)
	}

	/// Do not forward any values from `self` until `trigger` sends a `value`
	/// or `completed`, at which point the returned producer behaves exactly
	/// like `producer`.
	///
	/// - parameters:
	///   - trigger: A producer whose `value` or `completed` events will start
	///              the deliver of events on `self`.
	///
	/// - returns: A producer that will deliver events once the `trigger` sends
	///            `value` or `completed` events.
	public func skip<Trigger: SignalProducerConvertible>(
		until trigger: Trigger
	) -> SignalProducer<Value, Error> where Trigger.Value == (), Trigger.Error == Never {
		producer.skip(until: trigger)
	}

	/// Forward events from `self` with history: values of the returned producer
	/// are a tuples whose first member is the previous value and whose second member
	/// is the current value. `initial` is supplied as the first member when `self`
	/// sends its first value.
	///
	/// - parameters:
	///   - initial: A value that will be combined with the first value sent by
	///              `self`.
	///
	/// - returns: A producer that sends tuples that contain previous and current
	///            sent values of `self`.
	public func combinePrevious(_ initial: Value) -> SignalProducer<(Value, Value), Error> {
		producer.combinePrevious(initial)
	}

	/// Forward events from `self` with history: values of the produced signal
	/// are a tuples whose first member is the previous value and whose second member
	/// is the current value.
	///
	/// The produced `Signal` would not emit any tuple until it has received at least two
	/// values.
	///
	/// - returns: A producer that sends tuples that contain previous and current
	///            sent values of `self`.
	public func combinePrevious() -> SignalProducer<(Value, Value), Error> {
		producer.combinePrevious()
	}

	/// Combine all values from `self`, and forward the final result.
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
	/// - returns: A producer that sends the final result as `self` completes.
	public func reduce<U>(
		_ initialResult: U,
		_ nextPartialResult: @escaping (U, Value) -> U
	) -> SignalProducer<U, Error> {
		producer.reduce(initialResult, nextPartialResult)
	}

	/// Combine all values from `self`, and forward the final result.
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
	/// - returns: A producer that sends the final value as `self` completes.
	public func reduce<U>(
		into initialResult: U,
		_ nextPartialResult: @escaping (inout U, Value) -> Void
	) -> SignalProducer<U, Error> {
		producer.reduce(into: initialResult, nextPartialResult)
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
	/// - returns: A producer that sends the partial results of the accumuation, and the
	///            final result as `self` completes.
	public func scan<U>(
		_ initialResult: U,
		_ nextPartialResult: @escaping (U, Value) -> U
	) -> SignalProducer<U, Error> {
		producer.scan(initialResult, nextPartialResult)
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
	/// - returns: A producer that sends the partial results of the accumuation, and the
	///            final result as `self` completes.
	public func scan<U>(
		into initialResult: U,
		_ nextPartialResult: @escaping (inout U, Value) -> Void
	) -> SignalProducer<U, Error> {
		producer.scan(into: initialResult, nextPartialResult)
	}

	/// Accumulate all values from `self` as `State`, and send the value as `U`.
	///
	/// - parameters:
	///   - initialState: The state to use as the initial accumulating state.
	///   - next: A closure that combines the accumulating state and the latest value
	///           from `self`. The result would be "next state" and "output" where
	///           "output" would be forwarded and "next state" would be used in the
	///           next call of `next`.
	///
	/// - returns: A producer that sends the output that is computed from the accumuation.
	public func scanMap<State, U>(
		_ initialState: State,
		_ next: @escaping (State, Value) -> (State, U)
	) -> SignalProducer<U, Error> {
		producer.scanMap(initialState, next)
	}

	/// Accumulate all values from `self` as `State`, and send the value as `U`.
	///
	/// - parameters:
	///   - initialState: The state to use as the initial accumulating state.
	///   - next: A closure that combines the accumulating state and the latest value
	///           from `self`. The result would be "next state" and "output" where
	///           "output" would be forwarded and "next state" would be used in the
	///           next call of `next`.
	///
	/// - returns: A producer that sends the output that is computed from the accumuation.
	public func scanMap<State, U>(
		into initialState: State,
		_ next: @escaping (inout State, Value) -> U
	) -> SignalProducer<U, Error> {
		producer.scanMap(into: initialState, next)
	}

	/// Forward only values from `self` that are not considered equivalent to its
	/// immediately preceding value.
	///
	/// - note: The first value is always forwarded.
	///
	/// - parameters:
	///   - isEquivalent: A closure to determine whether two values are equivalent.
	///
	/// - returns: A producer which conditionally forwards values from `self`
	public func skipRepeats(_ isEquivalent: @escaping (Value, Value) -> Bool) -> SignalProducer<Value, Error> {
		producer.skipRepeats(isEquivalent)
	}

	/// Do not forward any value from `self` until `shouldContinue` returns `false`, at
	/// which point the returned signal starts to forward values from `self`, including
	/// the one leading to the toggling.
	///
	/// - parameters:
	///   - shouldContinue: A closure to determine whether the skipping should continue.
	///
	/// - returns: A producer which conditionally forwards values from `self`.
	public func skip(while shouldContinue: @escaping (Value) -> Bool) -> SignalProducer<Value, Error> {
		producer.skip(while: shouldContinue)
	}

	/// Forwards events from `self` until `replacement` begins sending events.
	///
	/// - parameters:
	///   - replacement: A producer to wait to wait for values from and start
	///                  sending them as a replacement to `self`'s values.
	///
	/// - returns: A producer which passes through `value`, `failed`, and
	///            `interrupted` events from `self` until `replacement` sends an
	///            event, at which point the returned producer will send that
	///            event and switch to passing through events from `replacement`
	///            instead, regardless of whether `self` has sent events
	///            already.
	public func take<Replacement: SignalProducerConvertible>(
		untilReplacement replacement: Replacement
	) -> SignalProducer<Value, Error> where Replacement.Value == Value, Replacement.Error == Error {
		producer.take(untilReplacement: replacement)
	}

	/// Wait until `self` completes and then forward the final `count` values
	/// on the returned producer.
	///
	/// - parameters:
	///   - count: Number of last events to send after `self` completes.
	///
	/// - returns: A producer that receives up to `count` values from `self`
	///            after `self` completes.
	public func take(last count: Int) -> SignalProducer<Value, Error> {
		producer.take(last: count)
	}

	/// Forward any values from `self` until `shouldContinue` returns `false`, at which
	/// point the produced `Signal` would complete.
	///
	/// - parameters:
	///   - shouldContinue: A closure to determine whether the forwarding of values should
	///                     continue.
	///
	/// - returns: A producer which conditionally forwards values from `self`.
	public func take(while shouldContinue: @escaping (Value) -> Bool) -> SignalProducer<Value, Error> {
		producer.take(while: shouldContinue)
	}

	/// Zip elements of two producers into pairs. The elements of any Nth pair
	/// are the Nth elements of the two input producers.
	///
	/// - parameters:
	///   - other: A producer to zip values with.
	///
	/// - returns: A producer that sends tuples of `self` and `otherProducer`.
	public func zip<Other: SignalProducerConvertible>(
		with other: Other
	) -> SignalProducer<(Value, Other.Value), Error> where Other.Error == Error {
		producer.zip(with: other)
	}

	/// Apply an action to every value from `self`, and forward the value if the action
	/// succeeds. If the action fails with an error, the produced `Signal` would propagate
	/// the failure and terminate.
	///
	/// - parameters:
	///   - action: An action which yields a `Result`.
	///
	/// - returns: A producer which forwards the values from `self` until the given action
	///            fails.
	public func attempt(_ action: @escaping (Value) -> Result<(), Error>) -> SignalProducer<Value, Error> {
		producer.attempt(action)
	}

	/// Apply a transform to every value from `self`, and forward the transformed value
	/// if the action succeeds. If the action fails with an error, the produced `Signal`
	/// would propagate the failure and terminate.
	///
	/// - parameters:
	///   - action: A transform which yields a `Result` of the transformed value or the
	///             error.
	///
	/// - returns: A producer which forwards the transformed values.
	public func attemptMap<U>(_ action: @escaping (Value) -> Result<U, Error>) -> SignalProducer<U, Error> {
		producer.attemptMap(action)
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
	///         value will be discarded and the returned producer will terminate
	///         immediately.
	///
	/// - note: If the device time changed backwards before previous date while
	///         a value is being throttled, and if there is a new value sent,
	///         the new value will be passed anyway.
	///
	/// - parameters:
	///   - interval: Number of seconds to wait between sent values.
	///   - scheduler: A scheduler to deliver events on.
	///
	/// - returns: A producer that sends values at least `interval` seconds
	///            appart on a given scheduler.
	public func throttle(_ interval: TimeInterval, on scheduler: DateScheduler) -> SignalProducer<Value, Error> {
		producer.throttle(interval, on: scheduler)
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
	/// - returns: A producer that sends values only while `shouldThrottle` is false.
	public func throttle<P: PropertyProtocol>(
		while shouldThrottle: P,
		on scheduler: Scheduler
	) -> SignalProducer<Value, Error> where P.Value == Bool {
		producer.throttle(while: shouldThrottle, on: scheduler)
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
	/// - note: If `self` terminates while a value is being debounced,
	///         the behaviour will be determined by `discardWhenCompleted`.
	///         If `true`, that value will be discarded and the returned producer
	///         will terminate immediately.
	///         If `false`, that value will be delivered at the next debounce
	///         interval.
	///
	/// - parameters:
	///   - interval: A number of seconds to wait before sending a value.
	///   - scheduler: A scheduler to send values on.
	///   - discardWhenCompleted: A boolean to indicate if the latest value
	///                             should be discarded on completion.
	///
	/// - returns: A producer that sends values that are sent from `self` at
	///            least `interval` seconds apart.
	public func debounce(
		_ interval: TimeInterval,
		on scheduler: DateScheduler,
		discardWhenCompleted: Bool = true
	) -> SignalProducer<Value, Error> {
		producer.debounce(interval, on: scheduler, discardWhenCompleted: discardWhenCompleted)
	}

	/// Forward events from `self` until `interval`. Then if producer isn't
	/// completed yet, fails with `error` on `scheduler`.
	///
	/// - note: If the interval is 0, the timeout will be scheduled immediately.
	///         The producer must complete synchronously (or on a faster
	///         scheduler) to avoid the timeout.
	///
	/// - parameters:
	///   - interval: Number of seconds to wait for `self` to complete.
	///   - error: Error to send with `failed` event if `self` is not completed
	///            when `interval` passes.
	///   - scheduler: A scheduler to deliver error on.
	///
	/// - returns: A producer that sends events for at most `interval` seconds,
	///            then, if not `completed` - sends `error` with `failed` event
	///            on `scheduler`.
	public func timeout(
		after interval: TimeInterval,
		raising error: Error,
		on scheduler: DateScheduler
	) -> SignalProducer<Value, Error> {
		producer.timeout(after: interval, raising: error, on: scheduler)
	}
	
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
	/// - returns: A producer that sends unique values during its lifetime.
	public func uniqueValues<Identity: Hashable>(
		_ transform: @escaping (Value) -> Identity
	) -> SignalProducer<Value, Error> {
		producer.uniqueValues(transform)
	}
	
	// Injects side effects to be performed upon the specified producer events.
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
		event: ((Signal<Value, Error>.Event) -> Void)? = nil,
		failed: ((Error) -> Void)? = nil,
		completed: (() -> Void)? = nil,
		interrupted: (() -> Void)? = nil,
		terminated: (() -> Void)? = nil,
		disposed: (() -> Void)? = nil,
		value: ((Value) -> Void)? = nil
	) -> SignalProducer<Value, Error> {
		producer.on(
			starting: starting,
			started: started,
			event: event,
			failed: failed,
			completed: completed,
			interrupted: interrupted,
			terminated: terminated,
			disposed: disposed,
			value: value
		)
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
		producer.start(on: scheduler)
	}
	
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
		producer.repeat(count)
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
		producer.retry(upTo: count)
	}

	/// Delays retrying on failure by `interval` up to `count` attempts.
	///
	/// - precondition: `count` must be non-negative integer.
	///
	/// - parameters:
	///   - count: Number of retries.
	///   - interval: An interval between invocations.
	///   - scheduler: A scheduler to deliver events on.
	///
	/// - returns: A signal producer that restarts up to `count` times.
	public func retry(upTo count: Int, interval: TimeInterval, on scheduler: DateScheduler) -> SignalProducer<Value, Error> {
		producer.retry(upTo: count, interval: interval, on: scheduler)
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
	public func then<Replacement: SignalProducerConvertible>(
		_ replacement: Replacement
	) -> SignalProducer<Replacement.Value, Error> where Replacement.Error == Never {
		producer.then(replacement)
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
	public func then<Replacement: SignalProducerConvertible>(
		_ replacement: Replacement
	) -> SignalProducer<Replacement.Value, Error> where Replacement.Error == Error {
		producer.then(replacement)
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
	public func then<Replacement: SignalProducerConvertible>(
		_ replacement: Replacement
	) -> SignalProducer<Value, Error> where Replacement.Value == Value, Replacement.Error == Error {
		producer.then(replacement)
	}
	
	/// Start the producer, then block, waiting for the first value.
	///
	/// When a single value or error is sent, the returned `Result` will
	/// represent those cases. However, when no values are sent, `nil` will be
	/// returned.
	///
	/// - returns: Result when single `value` or `failed` event is received.
	///            `nil` when no events are received.
	public func first() -> Result<Value, Error>? {
		producer.first()
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
		producer.single()
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
		producer.last()
	}

	/// Starts the producer, then blocks, waiting for completion.
	///
	/// When a completion or error is sent, the returned `Result` will represent
	/// those cases.
	///
	/// - returns: Result when single `completion` or `failed` event is
	///            received.
	public func wait() -> Result<(), Error> {
		producer.wait()
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
		producer.replayLazily(upTo: capacity)
	}
}

// MARK: - Optional

extension SignalProducerConvertible where Value: OptionalProtocol {
	/// Unwraps non-`nil` values and forwards them on the returned signal, `nil`
	/// values are dropped.
	///
	/// - returns: A producer that sends only non-nil values.
	public func skipNil() -> SignalProducer<Value.Wrapped, Error> {
		producer.skipNil()
	}
}

// MARK: - Event

extension SignalProducerConvertible where Value: EventProtocol, Error == Never {
	/// The inverse of materialize(), this will translate a producer of `Event`
	/// _values_ into a producer of those events themselves.
	///
	/// - returns: A producer that sends values carried by `self` events.
	public func dematerialize() -> SignalProducer<Value.Value, Value.Error> {
		producer.dematerialize()
	}
}

// MARK: - Error == Never

extension SignalProducerConvertible where Error == Never {
	/// Create a `Signal` from `self`, and observe the `Signal` for all values being
	/// emitted.
	///
	/// - parameters:
	///   - action: A closure to be invoked with values from the produced `Signal`.
	///
	/// - returns: A disposable to interrupt the produced `Signal`.
	@discardableResult
	public func startWithValues(_ action: @escaping (Value) -> Void) -> Disposable {
		producer.startWithValues(action)
	}
	
	/// The inverse of materializeResults(), this will translate a producer of `Result`
	/// _values_ into a producer of those events themselves.
	///
	/// - returns: A producer that sends values carried by `self` results.
	public func dematerializeResults<Success, Failure>()
	-> SignalProducer<Success, Failure> where Value == Result<Success, Failure> {
		producer.dematerializeResults()
	}
	
	/// Promote a producer that does not generate failures into one that can.
	///
	/// - note: This does not actually cause failers to be generated for the
	///         given producer, but makes it easier to combine with other
	///         producers that may fail; for example, with operators like
	///         `combineLatestWith`, `zipWith`, `flatten`, etc.
	///
	/// - parameters:
	///   - _ An `ErrorType`.
	///
	/// - returns: A producer that has an instantiatable `ErrorType`.
	public func promoteError<F>(_: F.Type = F.self) -> SignalProducer<Value, F> {
		producer.promoteError(F.self)
	}

	/// Promote a producer that does not generate failures into one that can.
	///
	/// - note: This does not actually cause failers to be generated for the
	///         given producer, but makes it easier to combine with other
	///         producers that may fail; for example, with operators like
	///         `combineLatestWith`, `zipWith`, `flatten`, etc.
	///
	/// - parameters:
	///   - _ An `ErrorType`.
	///
	/// - returns: A producer that has an instantiatable `ErrorType`.
	public func promoteError(_: Error.Type = Error.self) -> SignalProducer<Value, Error> {
		producer.promoteError(Error.self)
	}

	/// Forward events from `self` until `interval`. Then if producer isn't
	/// completed yet, fails with `error` on `scheduler`.
	///
	/// - note: If the interval is 0, the timeout will be scheduled immediately.
	///         The producer must complete synchronously (or on a faster
	///         scheduler) to avoid the timeout.
	///
	/// - parameters:
	///   - interval: Number of seconds to wait for `self` to complete.
	///   - error: Error to send with `failed` event if `self` is not completed
	///            when `interval` passes.
	///   - scheudler: A scheduler to deliver error on.
	///
	/// - returns: A producer that sends events for at most `interval` seconds,
	///            then, if not `completed` - sends `error` with `failed` event
	///            on `scheduler`.
	public func timeout<NewError>(
		after interval: TimeInterval,
		raising error: NewError,
		on scheduler: DateScheduler
	) -> SignalProducer<Value, NewError> {
		producer.timeout(after: interval, raising: error, on: scheduler)
	}

	/// Apply a throwable action to every value from `self`, and forward the values
	/// if the action succeeds. If the action throws an error, the produced `Signal`
	/// would propagate the failure and terminate.
	///
	/// - parameters:
	///   - action: A throwable closure to perform an arbitrary action on the value.
	///
	/// - returns: A producer which forwards the successful values of the given action.
	public func attempt(_ action: @escaping (Value) throws -> Void) -> SignalProducer<Value, Swift.Error> {
		producer.attempt(action)
	}

	/// Apply a throwable action to every value from `self`, and forward the results
	/// if the action succeeds. If the action throws an error, the produced `Signal`
	/// would propagate the failure and terminate.
	///
	/// - parameters:
	///   - action: A throwable closure to perform an arbitrary action on the value, and
	///             yield a result.
	///
	/// - returns: A producer which forwards the successful results of the given action.
	public func attemptMap<U>(_ action: @escaping (Value) throws -> U) -> SignalProducer<U, Swift.Error> {
		producer.attemptMap(action)
	}
	
	/// Promote a producer that does not generate values, as indicated by `Never`,
	/// to be a producer of the given type of value.
	///
	/// - note: The promotion does not result in any value being generated.
	///
	/// - parameters:
	///   - _ The type of value to promote to.
	///
	/// - returns: A producer that forwards all terminal events from `self`.
	public func promoteValue<U>(_: U.Type = U.self) -> SignalProducer<U, Error> {
		producer.promoteValue(U.self)
	}

	/// Promote a producer that does not generate values, as indicated by `Never`,
	/// to be a producer of the given type of value.
	///
	/// - note: The promotion does not result in any value being generated.
	///
	/// - parameters:
	///   - _ The type of value to promote to.
	///
	/// - returns: A producer that forwards all terminal events from `self`.
	public func promoteValue(_: Value.Type = Value.self) -> SignalProducer<Value, Error> {
		producer.promoteValue(Value.self)
	}

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
	public func then<Replacement: SignalProducerConvertible>(
		_ replacement: Replacement
	) -> SignalProducer<Replacement.Value, Replacement.Error> {
		producer.then(replacement)
	}

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
	public func then<Replacement: SignalProducerConvertible>(
		_ replacement: Replacement
	) -> SignalProducer<Replacement.Value, Never> where Replacement.Error == Never {
		producer.then(replacement)
	}

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
	public func then<Replacement: SignalProducerConvertible>(
		_ replacement: Replacement
	) -> SignalProducer<Value, Never> where Replacement.Value == Value, Replacement.Error == Never {
		producer.then(replacement)
	}
}

// MARK: Error == Swift.Error

extension SignalProducerConvertible where Error == Swift.Error {
	/// Apply a throwable action to every value from `self`, and forward the values
	/// if the action succeeds. If the action throws an error, the produced `Signal`
	/// would propagate the failure and terminate.
	///
	/// - parameters:
	///   - action: A throwable closure to perform an arbitrary action on the value.
	///
	/// - returns: A producer which forwards the successful values of the given action.
	public func attempt(_ action: @escaping (Value) throws -> Void) -> SignalProducer<Value, Error> {
		producer.attempt(action)
	}

	/// Apply a throwable transform to every value from `self`, and forward the results
	/// if the action succeeds. If the transform throws an error, the produced `Signal`
	/// would propagate the failure and terminate.
	///
	/// - parameters:
	///   - transform: A throwable transform.
	///
	/// - returns: A producer which forwards the successfully transformed values.
	public func attemptMap<U>(_ transform: @escaping (Value) throws -> U) -> SignalProducer<U, Error> {
		producer.attemptMap(transform)
	}
}

// MARK: Value == Never

extension SignalProducerConvertible where Value == Never {
	/// Promote a producer that does not generate values, as indicated by `Never`,
	/// to be a producer of the given type of value.
	///
	/// - note: The promotion does not result in any value being generated.
	///
	/// - parameters:
	///   - _ The type of value to promote to.
	///
	/// - returns: A producer that forwards all terminal events from `self`.
	public func promoteValue<U>(_: U.Type = U.self) -> SignalProducer<U, Error> {
		producer.promoteValue(U.self)
	}

	/// Promote a producer that does not generate values, as indicated by `Never`,
	/// to be a producer of the given type of value.
	///
	/// - note: The promotion does not result in any value being generated.
	///
	/// - parameters:
	///   - _ The type of value to promote to.
	///
	/// - returns: A producer that forwards all terminal events from `self`.
	public func promoteValue(_: Value.Type = Value.self) -> SignalProducer<Value, Error> {
		producer.promoteValue(Value.self)
	}
}

// MARK: Value: Equatable

extension SignalProducerConvertible where Value: Equatable {
	/// Forward only values from `self` that are not equal to its immediately preceding
	/// value.
	///
	/// - note: The first value is always forwarded.
	///
	/// - returns: A producer which conditionally forwards values from `self`.
	public func skipRepeats() -> SignalProducer<Value, Error> {
		producer.skipRepeats()
	}
}

// MARK: Value: Hashable

extension SignalProducerConvertible where Value: Hashable {
	/// Forward only those values from `self` that are unique across the set of
	/// all values that have been seen.
	///
	/// - note: This causes the values to be retained to check for uniqueness.
	///         Providing a function that returns a unique value for each sent
	///         value can help you reduce the memory footprint.
	///
	/// - returns: A producer that sends unique values during its lifetime.
	public func uniqueValues() -> SignalProducer<Value, Error> {
		producer.uniqueValues()
	}
}

// MARK: Value == Bool

extension SignalProducerConvertible where Value == Bool {
	/// Create a producer that computes a logical NOT in the latest values of `self`.
	///
	/// - returns: A producer that emits the logical NOT results.
	public func negate() -> SignalProducer<Value, Error> {
		producer.map(!)
	}

	/// Create a producer that computes a logical AND between the latest values of `self`
	/// and `producer`.
	///
	/// - parameters:
	///   - booleans: A producer of booleans to be combined with `self`.
	///
	/// - returns: A producer that emits the logical AND results.
	public func and<Booleans: SignalProducerConvertible>(
		_ booleans: Booleans
	) -> SignalProducer<Value, Error> where Booleans.Value == Value, Booleans.Error == Error {
		producer.and(booleans)
	}

	/// Create a producer that computes a logical OR between the latest values of `self`
	/// and `producer`.
	///
	/// - parameters:
	///   - booleans: A producer of booleans to be combined with `self`.
	///
	/// - returns: A producer that emits the logical OR results.
	public func or<Booleans: SignalProducerConvertible>(
		_ booleans: Booleans
	) -> SignalProducer<Value, Error> where Booleans.Value == Value, Booleans.Error == Error {
		producer.or(booleans)
	}
}
