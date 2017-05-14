import Dispatch
import Foundation
import Result

extension SignalProducer {
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
	public func lift<U, F>(_ transform: @escaping (Signal<Value, Error>) -> Signal<U, F>) -> SignalProducer<U, F> {
		return SignalProducer<U, F> { observer, outerDisposable in
			self.startWithSignal { signal, innerDisposable in
				outerDisposable += innerDisposable

				transform(signal).observe(observer)
			}
		}
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
	public func lift<U, F, V, G>(_ transform: @escaping (Signal<Value, Error>) -> (Signal<U, F>) -> Signal<V, G>) -> (SignalProducer<U, F>) -> SignalProducer<V, G> {
		return liftRight(transform)
	}

	/// Right-associative lifting of a binary signal operator over producers.
	/// That is, the argument producer will be started before the receiver. When
	/// both producers are synchronous this order can be important depending on
	/// the operator to generate correct results.
	fileprivate func liftRight<U, F, V, G>(_ transform: @escaping (Signal<Value, Error>) -> (Signal<U, F>) -> Signal<V, G>) -> (SignalProducer<U, F>) -> SignalProducer<V, G> {
		return { otherProducer in
			return SignalProducer<V, G> { observer, outerDisposable in
				self.startWithSignal { signal, disposable in
					outerDisposable.add(disposable)

					otherProducer.startWithSignal { otherSignal, otherDisposable in
						outerDisposable += otherDisposable

						transform(signal)(otherSignal).observe(observer)
					}
				}
			}
		}
	}

	/// Left-associative lifting of a binary signal operator over producers.
	/// That is, the receiver will be started before the argument producer. When
	/// both producers are synchronous this order can be important depending on
	/// the operator to generate correct results.
	fileprivate func liftLeft<U, F, V, G>(_ transform: @escaping (Signal<Value, Error>) -> (Signal<U, F>) -> Signal<V, G>) -> (SignalProducer<U, F>) -> SignalProducer<V, G> {
		return { otherProducer in
			return SignalProducer<V, G> { observer, outerDisposable in
				otherProducer.startWithSignal { otherSignal, otherDisposable in
					outerDisposable += otherDisposable

					self.startWithSignal { signal, disposable in
						outerDisposable.add(disposable)

						transform(signal)(otherSignal).observe(observer)
					}
				}
			}
		}
	}

	/// Lift a binary Signal operator to operate upon a Signal and a
	/// SignalProducer instead.
	///
	/// In other words, this will create a new `SignalProducer` which will apply
	/// the given `Signal` operator to _every_ `Signal` created from the two
	/// producers, just as if the operator had been applied to each `Signal`
	/// yielded from `start()`.
	///
	/// - parameters:
	///   - transform: A binary operator to lift.
	///
	/// - returns: A binary operator that works on `Signal` and returns
	///            `SignalProducer`.
	public func lift<U, F, V, G>(_ transform: @escaping (Signal<Value, Error>) -> (Signal<U, F>) -> Signal<V, G>) -> (Signal<U, F>) -> SignalProducer<V, G> {
		return { otherSignal in
			return self.liftRight(transform)(SignalProducer<U, F>(otherSignal))
		}
	}
}

/// Start the producers in the argument order.
///
/// - parameters:
///   - disposable: The `CompositeDisposable` to collect the interrupt handles of all
///                 produced `Signal`s.
///   - setup: The closure to accept all produced `Signal`s at once.
private func flattenStart<A, B, Error>(_ disposable: CompositeDisposable, _ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>, _ setup: (Signal<A, Error>, Signal<B, Error>) -> Void) {
	b.startWithSignal(interruptingBy: disposable) { b in
		a.startWithSignal(interruptingBy: disposable) { setup($0, b) }
	}
}

/// Start the producers in the argument order.
///
/// - parameters:
///   - disposable: The `CompositeDisposable` to collect the interrupt handles of all
///                 produced `Signal`s.
///   - setup: The closure to accept all produced `Signal`s at once.
private func flattenStart<A, B, C, Error>(_ disposable: CompositeDisposable, _ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ setup: (Signal<A, Error>, Signal<B, Error>, Signal<C, Error>) -> Void) {
	c.startWithSignal(interruptingBy: disposable) { c in
		flattenStart(disposable, a, b) { setup($0, $1, c) }
	}
}

/// Start the producers in the argument order.
///
/// - parameters:
///   - disposable: The `CompositeDisposable` to collect the interrupt handles of all
///                 produced `Signal`s.
///   - setup: The closure to accept all produced `Signal`s at once.
private func flattenStart<A, B, C, D, Error>(_ disposable: CompositeDisposable, _ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ setup: (Signal<A, Error>, Signal<B, Error>, Signal<C, Error>, Signal<D, Error>) -> Void) {
	d.startWithSignal(interruptingBy: disposable) { d in
		flattenStart(disposable, a, b, c) { setup($0, $1, $2, d) }
	}
}

/// Start the producers in the argument order.
///
/// - parameters:
///   - disposable: The `CompositeDisposable` to collect the interrupt handles of all
///                 produced `Signal`s.
///   - setup: The closure to accept all produced `Signal`s at once.
private func flattenStart<A, B, C, D, E, Error>(_ disposable: CompositeDisposable, _ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ setup: (Signal<A, Error>, Signal<B, Error>, Signal<C, Error>, Signal<D, Error>, Signal<E, Error>) -> Void) {
	e.startWithSignal(interruptingBy: disposable) { e in
		flattenStart(disposable, a, b, c, d) { setup($0, $1, $2, $3, e) }
	}
}

/// Start the producers in the argument order.
///
/// - parameters:
///   - disposable: The `CompositeDisposable` to collect the interrupt handles of all
///                 produced `Signal`s.
///   - setup: The closure to accept all produced `Signal`s at once.
private func flattenStart<A, B, C, D, E, F, Error>(_ disposable: CompositeDisposable, _ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ setup: (Signal<A, Error>, Signal<B, Error>, Signal<C, Error>, Signal<D, Error>, Signal<E, Error>, Signal<F, Error>) -> Void) {
	f.startWithSignal(interruptingBy: disposable) { f in
		flattenStart(disposable, a, b, c, d, e) { setup($0, $1, $2, $3, $4, f) }
	}
}

/// Start the producers in the argument order.
///
/// - parameters:
///   - disposable: The `CompositeDisposable` to collect the interrupt handles of all
///                 produced `Signal`s.
///   - setup: The closure to accept all produced `Signal`s at once.
private func flattenStart<A, B, C, D, E, F, G, Error>(_ disposable: CompositeDisposable, _ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>, _ setup: (Signal<A, Error>, Signal<B, Error>, Signal<C, Error>, Signal<D, Error>, Signal<E, Error>, Signal<F, Error>, Signal<G, Error>) -> Void) {
	g.startWithSignal(interruptingBy: disposable) { g in
		flattenStart(disposable, a, b, c, d, e, f) { setup($0, $1, $2, $3, $4, $5, g) }
	}
}

/// Start the producers in the argument order.
///
/// - parameters:
///   - disposable: The `CompositeDisposable` to collect the interrupt handles of all
///                 produced `Signal`s.
///   - setup: The closure to accept all produced `Signal`s at once.
private func flattenStart<A, B, C, D, E, F, G, H, Error>(_ disposable: CompositeDisposable, _ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>, _ h: SignalProducer<H, Error>, _ setup: (Signal<A, Error>, Signal<B, Error>, Signal<C, Error>, Signal<D, Error>, Signal<E, Error>, Signal<F, Error>, Signal<G, Error>, Signal<H, Error>) -> Void) {
	h.startWithSignal(interruptingBy: disposable) { h in
		flattenStart(disposable, a, b, c, d, e, f, g) { setup($0, $1, $2, $3, $4, $5, $6, h) }
	}
}

/// Start the producers in the argument order.
///
/// - parameters:
///   - disposable: The `CompositeDisposable` to collect the interrupt handles of all
///                 produced `Signal`s.
///   - setup: The closure to accept all produced `Signal`s at once.
private func flattenStart<A, B, C, D, E, F, G, H, I, Error>(_ disposable: CompositeDisposable, _ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>, _ h: SignalProducer<H, Error>, _ i: SignalProducer<I, Error>, _ setup: (Signal<A, Error>, Signal<B, Error>, Signal<C, Error>, Signal<D, Error>, Signal<E, Error>, Signal<F, Error>, Signal<G, Error>, Signal<H, Error>, Signal<I, Error>) -> Void) {
	i.startWithSignal(interruptingBy: disposable) { i in
		flattenStart(disposable, a, b, c, d, e, f, g, h) { setup($0, $1, $2, $3, $4, $5, $6, $7, i) }
	}
}

/// Start the producers in the argument order.
///
/// - parameters:
///   - disposable: The `CompositeDisposable` to collect the interrupt handles of all
///                 produced `Signal`s.
///   - setup: The closure to accept all produced `Signal`s at once.
private func flattenStart<A, B, C, D, E, F, G, H, I, J, Error>(_ disposable: CompositeDisposable, _ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>, _ h: SignalProducer<H, Error>, _ i: SignalProducer<I, Error>, _ j: SignalProducer<J, Error>, _ setup: (Signal<A, Error>, Signal<B, Error>, Signal<C, Error>, Signal<D, Error>, Signal<E, Error>, Signal<F, Error>, Signal<G, Error>, Signal<H, Error>, Signal<I, Error>, Signal<J, Error>) -> Void) {
	j.startWithSignal(interruptingBy: disposable) { j in
		flattenStart(disposable, a, b, c, d, e, f, g, h, i) { setup($0, $1, $2, $3, $4, $5, $6, $7, $8, j) }
	}
}

extension SignalProducer {
	/// Map each value in the producer to a new value.
	///
	/// - parameters:
	///   - transform: A closure that accepts a value and returns a different
	///                value.
	///
	/// - returns: A signal producer that, when started, will send a mapped
	///            value of `self.`
	public func map<U>(_ transform: @escaping (Value) -> U) -> SignalProducer<U, Error> {
		return lift { $0.map(transform) }
	}

	/// Map errors in the producer to a new error.
	///
	/// - parameters:
	///   - transform: A closure that accepts an error object and returns a
	///                different error.
	///
	/// - returns: A producer that emits errors of new type.
	public func mapError<F>(_ transform: @escaping (Error) -> F) -> SignalProducer<Value, F> {
		return lift { $0.mapError(transform) }
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
		return lift { $0.lazyMap(on: scheduler, transform: transform) }
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
		return lift { $0.filter(isIncluded) }
	}

	/// Applies `transform` to values from the producer and forwards values with non `nil` results unwrapped.
	/// - parameters:
	///   - transform: A closure that accepts a value from the `value` event and
	///                returns a new optional value.
	///
	/// - returns: A producer that will send new values, that are non `nil` after the transformation.
	public func filterMap<U>(_ transform: @escaping (Value) -> U?) -> SignalProducer<U, Error> {
		return lift { $0.filterMap(transform) }
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
		return lift { $0.take(first: count) }
	}

	/// Yield an array of values when `self` completes.
	///
	/// - note: When `self` completes without collecting any value, it will send
	///         an empty array of values.
	///
	/// - returns: A producer that, when started, will yield an array of values
	///            when `self` completes.
	public func collect() -> SignalProducer<[Value], Error> {
		return lift { $0.collect() }
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
		precondition(count > 0)
		return lift { $0.collect(count: count) }
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
	/// let (producer, observer) = SignalProducer<Int, NoError>.buffer(1)
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
	/// - returns: A signal of arrays of values, as instructed by the `shouldEmit`
	///            closure.
	public func collect(_ shouldEmit: @escaping (_ values: [Value]) -> Bool) -> SignalProducer<[Value], Error> {
		return lift { $0.collect(shouldEmit) }
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
	/// let (producer, observer) = SignalProducer<Int, NoError>.buffer(1)
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
	public func collect(_ shouldEmit: @escaping (_ collected: [Value], _ latest: Value) -> Bool) -> SignalProducer<[Value], Error> {
		return lift { $0.collect(shouldEmit) }
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
		return lift { $0.observe(on: scheduler) }
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
	public func combineLatest<U>(with other: SignalProducer<U, Error>) -> SignalProducer<(Value, U), Error> {
		return SignalProducer.combineLatest(self, other)
	}

	/// Combine the latest value of the receiver with the latest value from
	/// the given signal.
	///
	/// - note: The returned producer will not send a value until both inputs
	///         have sent at least one value each.
	///
	/// - note: If either input is interrupted, the returned producer will also
	///         be interrupted.
	///
	/// - note: The returned producer will not complete until both inputs
	///         complete.
	///
	/// - parameters:
	///   - other: A signal to combine `self`'s value with.
	///
	/// - returns: A producer that, when started, will yield a tuple containing
	///            values of `self` and given signal.
	public func combineLatest<U>(with other: Signal<U, Error>) -> SignalProducer<(Value, U), Error> {
		return SignalProducer.combineLatest(self, SignalProducer<U, Error>(other))
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
		return lift { $0.delay(interval, on: scheduler) }
	}

	/// Skip the first `count` values, then forward everything afterward.
	///
	/// - parameters:
	///   - count: A number of values to skip.
	///
	/// - returns:  A producer that, when started, will skip the first `count`
	///             values, then forward everything afterward.
	public func skip(first count: Int) -> SignalProducer<Value, Error> {
		return lift { $0.skip(first: count) }
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
	public func materialize() -> SignalProducer<ProducedSignal.Event, NoError> {
		return lift { $0.materialize() }
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
	public func sample<T>(with sampler: SignalProducer<T, NoError>) -> SignalProducer<(Value, T), Error> {
		return liftLeft(Signal.sample(with:))(sampler)
	}

	/// Forward the latest value from `self` with the value from `sampler` as a
	/// tuple, only when `sampler` sends a `value` event.
	///
	/// - note: If `sampler` fires before a value has been observed on `self`,
	///         nothing happens.
	///
	/// - parameters:
	///   - sampler: A signal that will trigger the delivery of `value` event
	///              from `self`.
	///
	/// - returns: A producer that, when started, will send values from `self`
	///            and `sampler`, sampled (possibly multiple times) by
	///            `sampler`, then complete once both input producers have
	///            completed, or interrupt if either input producer is
	///            interrupted.
	public func sample<T>(with sampler: Signal<T, NoError>) -> SignalProducer<(Value, T), Error> {
		return lift(Signal.sample(with:))(sampler)
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
	public func sample(on sampler: SignalProducer<(), NoError>) -> SignalProducer<Value, Error> {
		return liftLeft(Signal.sample(on:))(sampler)
	}

	/// Forward the latest value from `self` whenever `sampler` sends a `value`
	/// event.
	///
	/// - note: If `sampler` fires before a value has been observed on `self`,
	///         nothing happens.
	///
	/// - parameters:
	///   - trigger: A signal whose `value` or `completed` events will start the
	///              deliver of events on `self`.
	///
	/// - returns: A producer that will send values from `self`, sampled
	///            (possibly multiple times) by `sampler`, then complete once
	///            both inputs have completed, or interrupt if either input is
	///            interrupted.
	public func sample(on sampler: Signal<(), NoError>) -> SignalProducer<Value, Error> {
		return lift(Signal.sample(on:))(sampler)
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
	public func withLatest<U>(from samplee: SignalProducer<U, NoError>) -> SignalProducer<(Value, U), Error> {
		return liftRight(Signal.withLatest)(samplee)
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
	public func withLatest<U>(from samplee: Signal<U, NoError>) -> SignalProducer<(Value, U), Error> {
		return lift(Signal.withLatest)(samplee)
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
		return lift { $0.take(during: lifetime) }
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
	public func take(until trigger: SignalProducer<(), NoError>) -> SignalProducer<Value, Error> {
		return liftRight(Signal.take(until:))(trigger)
	}

	/// Forward events from `self` until `trigger` sends a `value` or
	/// `completed` event, at which point the returned producer will complete.
	///
	/// - parameters:
	///   - trigger: A signal whose `value` or `completed` events will stop the
	///              delivery of `value` events from `self`.
	///
	/// - returns: A producer that will deliver events until `trigger` sends
	///            `value` or `completed` events.
	public func take(until trigger: Signal<(), NoError>) -> SignalProducer<Value, Error> {
		return lift(Signal.take(until:))(trigger)
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
	public func skip(until trigger: SignalProducer<(), NoError>) -> SignalProducer<Value, Error> {
		return liftRight(Signal.skip(until:))(trigger)
	}

	/// Do not forward any values from `self` until `trigger` sends a `value`
	/// or `completed`, at which point the returned signal behaves exactly like
	/// `signal`.
	///
	/// - parameters:
	///   - trigger: A signal whose `value` or `completed` events will start the
	///              deliver of events on `self`.
	///
	/// - returns: A producer that will deliver events once the `trigger` sends
	///            `value` or `completed` events.
	public func skip(until trigger: Signal<(), NoError>) -> SignalProducer<Value, Error> {
		return lift(Signal.skip(until:))(trigger)
	}

	/// Forward events from `self` with history: values of the returned producer
	/// are a tuple whose first member is the previous value and whose second
	/// member is the current value. `initial` is supplied as the first member
	/// when `self` sends its first value.
	///
	/// - parameters:
	///   - initial: A value that will be combined with the first value sent by
	///              `self`.
	///
	/// - returns: A producer that sends tuples that contain previous and
	///            current sent values of `self`.
	public func combinePrevious(_ initial: Value) -> SignalProducer<(Value, Value), Error> {
		return lift { $0.combinePrevious(initial) }
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
	public func reduce<U>(_ initialResult: U, _ nextPartialResult: @escaping (U, Value) -> U) -> SignalProducer<U, Error> {
		return lift { $0.reduce(initialResult, nextPartialResult) }
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
	public func reduce<U>(into initialResult: U, _ nextPartialResult: @escaping (inout U, Value) -> Void) -> SignalProducer<U, Error> {
		return lift { $0.reduce(into: initialResult, nextPartialResult) }
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
	public func scan<U>(_ initialResult: U, _ nextPartialResult: @escaping (U, Value) -> U) -> SignalProducer<U, Error> {
		return lift { $0.scan(initialResult, nextPartialResult) }
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
	public func scan<U>(into initialResult: U, _ nextPartialResult: @escaping (inout U, Value) -> Void) -> SignalProducer<U, Error> {
		return lift { $0.scan(into: initialResult, nextPartialResult) }
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
		return lift { $0.skipRepeats(isEquivalent) }
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
		return lift { $0.skip(while: shouldContinue) }
	}

	/// Forward events from `self` until `replacement` begins sending events.
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
	public func take(untilReplacement signal: SignalProducer<Value, Error>) -> SignalProducer<Value, Error> {
		return liftRight(Signal.take(untilReplacement:))(signal)
	}

	/// Forwards events from `self` until `replacement` begins sending events.
	///
	/// - parameters:
	///   - replacement: A signal to wait to wait for values from and start
	///                  sending them as a replacement to `self`'s values.
	///
	/// - returns: A producer which passes through `value`, `failed`, and
	///            `interrupted` events from `self` until `replacement` sends an
	///            event, at which point the returned producer will send that
	///            event and switch to passing through events from `replacement`
	///            instead, regardless of whether `self` has sent events
	///            already.
	public func take(untilReplacement signal: Signal<Value, Error>) -> SignalProducer<Value, Error> {
		return lift(Signal.take(untilReplacement:))(signal)
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
		return lift { $0.take(last: count) }
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
		return lift { $0.take(while: shouldContinue) }
	}

	/// Zip elements of two producers into pairs. The elements of any Nth pair
	/// are the Nth elements of the two input producers.
	///
	/// - parameters:
	///   - other: A producer to zip values with.
	///
	/// - returns: A producer that sends tuples of `self` and `otherProducer`.
	public func zip<U>(with other: SignalProducer<U, Error>) -> SignalProducer<(Value, U), Error> {
		return SignalProducer.zip(self, other)
	}

	/// Zip elements of this producer and a signal into pairs. The elements of
	/// any Nth pair are the Nth elements of the two.
	///
	/// - parameters:
	///   - other: A signal to zip values with.
	///
	/// - returns: A producer that sends tuples of `self` and `otherSignal`.
	public func zip<U>(with other: Signal<U, Error>) -> SignalProducer<(Value, U), Error> {
		return SignalProducer.zip(self, SignalProducer<U, Error>(other))
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
		return lift { $0.attempt(action) }
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
		return lift { $0.attemptMap(action) }
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
		return lift { $0.throttle(interval, on: scheduler) }
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
	public func throttle<P: PropertyProtocol>(while shouldThrottle: P, on scheduler: Scheduler) -> SignalProducer<Value, Error>
		where P.Value == Bool
	{
		// Using `Property.init(_:)` avoids capturing a strong reference
		// to `shouldThrottle`, so that we don't extend its lifetime.
		let shouldThrottle = Property(shouldThrottle)

		return lift { $0.throttle(while: shouldThrottle, on: scheduler) }
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
	///         that value will be discarded and the returned producer will
	///         terminate immediately.
	///
	/// - parameters:
	///   - interval: A number of seconds to wait before sending a value.
	///   - scheduler: A scheduler to send values on.
	///
	/// - returns: A producer that sends values that are sent from `self` at
	///            least `interval` seconds apart.
	public func debounce(_ interval: TimeInterval, on scheduler: DateScheduler) -> SignalProducer<Value, Error> {
		return lift { $0.debounce(interval, on: scheduler) }
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
	public func timeout(after interval: TimeInterval, raising error: Error, on scheduler: DateScheduler) -> SignalProducer<Value, Error> {
		return lift { $0.timeout(after: interval, raising: error, on: scheduler) }
	}
}

extension SignalProducer where Value: OptionalProtocol {
	/// Unwraps non-`nil` values and forwards them on the returned signal, `nil`
	/// values are dropped.
	///
	/// - returns: A producer that sends only non-nil values.
	public func skipNil() -> SignalProducer<Value.Wrapped, Error> {
		return lift { $0.skipNil() }
	}
}

extension SignalProducer where Value: EventProtocol, Error == NoError {
	/// The inverse of materialize(), this will translate a producer of `Event`
	/// _values_ into a producer of those events themselves.
	///
	/// - returns: A producer that sends values carried by `self` events.
	public func dematerialize() -> SignalProducer<Value.Value, Value.Error> {
		return lift { $0.dematerialize() }
	}
}

extension SignalProducer where Error == NoError {
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
	public func promoteErrors<F: Swift.Error>(_: F.Type) -> SignalProducer<Value, F> {
		return lift { $0.promoteErrors(F.self) }
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
	public func timeout<NewError: Swift.Error>(
		after interval: TimeInterval,
		raising error: NewError,
		on scheduler: DateScheduler
		) -> SignalProducer<Value, NewError> {
		return lift { $0.timeout(after: interval, raising: error, on: scheduler) }
	}

	/// Apply a throwable action to every value from `self`, and forward the values
	/// if the action succeeds. If the action throws an error, the produced `Signal`
	/// would propagate the failure and terminate.
	///
	/// - parameters:
	///   - action: A throwable closure to perform an arbitrary action on the value.
	///
	/// - returns: A producer which forwards the successful values of the given action.
	public func attempt(_ action: @escaping (Value) throws -> Void) -> SignalProducer<Value, AnyError> {
		return lift { $0.attempt(action) }
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
	public func attemptMap<U>(_ action: @escaping (Value) throws -> U) -> SignalProducer<U, AnyError> {
		return lift { $0.attemptMap(action) }
	}
}

extension SignalProducer where Error == AnyError {
	/// Apply a throwable action to every value from `self`, and forward the values
	/// if the action succeeds. If the action throws an error, the produced `Signal`
	/// would propagate the failure and terminate.
	///
	/// - parameters:
	///   - action: A throwable closure to perform an arbitrary action on the value.
	///
	/// - returns: A producer which forwards the successful values of the given action.
	public func attempt(_ action: @escaping (Value) throws -> Void) -> SignalProducer<Value, AnyError> {
		return lift { $0.attempt(action) }
	}

	/// Apply a throwable transform to every value from `self`, and forward the results
	/// if the action succeeds. If the transform throws an error, the produced `Signal`
	/// would propagate the failure and terminate.
	///
	/// - parameters:
	///   - transform: A throwable transform.
	///
	/// - returns: A producer which forwards the successfully transformed values.
	public func attemptMap<U>(_ transform: @escaping (Value) throws -> U) -> SignalProducer<U, AnyError> {
		return lift { $0.attemptMap(transform) }
	}
}

extension SignalProducer where Value: Equatable {
	/// Forward only values from `self` that are not equal to its immediately preceding
	/// value.
	///
	/// - note: The first value is always forwarded.
	///
	/// - returns: A property which conditionally forwards values from `self`.
	public func skipRepeats() -> SignalProducer<Value, Error> {
		return lift { $0.skipRepeats() }
	}
}

extension SignalProducer {
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
	public func uniqueValues<Identity: Hashable>(_ transform: @escaping (Value) -> Identity) -> SignalProducer<Value, Error> {
		return lift { $0.uniqueValues(transform) }
	}
}

extension SignalProducer where Value: Hashable {
	/// Forward only those values from `self` that are unique across the set of
	/// all values that have been seen.
	///
	/// - note: This causes the values to be retained to check for uniqueness.
	///         Providing a function that returns a unique value for each sent
	///         value can help you reduce the memory footprint.
	///
	/// - returns: A producer that sends unique values during its lifetime.
	public func uniqueValues() -> SignalProducer<Value, Error> {
		return lift { $0.uniqueValues() }
	}
}

extension SignalProducer {
	/// Combines the values of all the given producers, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>) -> SignalProducer<(Value, B), Error> {
		return SignalProducer<(Value, B), Error> { observer, disposable in
			flattenStart(disposable, a, b) { Signal.combineLatest($0, $1).observe(observer) }
		}
	}

	/// Combines the values of all the given producers, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>) -> SignalProducer<(Value, B, C), Error> {
		return SignalProducer<(Value, B, C), Error> { observer, disposable in
			flattenStart(disposable, a, b, c) { Signal.combineLatest($0, $1, $2).observe(observer) }
		}
	}

	/// Combines the values of all the given producers, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>) -> SignalProducer<(Value, B, C, D), Error> {
		return SignalProducer<(Value, B, C, D), Error> { observer, disposable in
			flattenStart(disposable, a, b, c, d) { Signal.combineLatest($0, $1, $2, $3).observe(observer) }
		}
	}

	/// Combines the values of all the given producers, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D, E>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>) -> SignalProducer<(Value, B, C, D, E), Error> {
		return SignalProducer<(Value, B, C, D, E), Error> { observer, disposable in
			flattenStart(disposable, a, b, c, d, e) { Signal.combineLatest($0, $1, $2, $3, $4).observe(observer) }
		}
	}

	/// Combines the values of all the given producers, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D, E, F>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>) -> SignalProducer<(Value, B, C, D, E, F), Error> {
		return SignalProducer<(Value, B, C, D, E, F), Error> { observer, disposable in
			flattenStart(disposable, a, b, c, d, e, f) { Signal.combineLatest($0, $1, $2, $3, $4, $5).observe(observer) }
		}
	}

	/// Combines the values of all the given producers, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D, E, F, G>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>) -> SignalProducer<(Value, B, C, D, E, F, G), Error> {
		return SignalProducer<(Value, B, C, D, E, F, G), Error> { observer, disposable in
			flattenStart(disposable, a, b, c, d, e, f, g) { Signal.combineLatest($0, $1, $2, $3, $4, $5, $6).observe(observer) }
		}
	}

	/// Combines the values of all the given producers, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D, E, F, G, H>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>, _ h: SignalProducer<H, Error>) -> SignalProducer<(Value, B, C, D, E, F, G, H), Error> {
		return SignalProducer<(Value, B, C, D, E, F, G, H), Error> { observer, disposable in
			flattenStart(disposable, a, b, c, d, e, f, g, h) { Signal.combineLatest($0, $1, $2, $3, $4, $5, $6, $7).observe(observer) }
		}
	}

	/// Combines the values of all the given producers, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D, E, F, G, H, I>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>, _ h: SignalProducer<H, Error>, _ i: SignalProducer<I, Error>) -> SignalProducer<(Value, B, C, D, E, F, G, H, I), Error> {
		return SignalProducer<(Value, B, C, D, E, F, G, H, I), Error> { observer, disposable in
			flattenStart(disposable, a, b, c, d, e, f, g, h, i) { Signal.combineLatest($0, $1, $2, $3, $4, $5, $6, $7, $8).observe(observer) }
		}
	}

	/// Combines the values of all the given producers, in the manner described by
	/// `combineLatest(with:)`.
	public static func combineLatest<B, C, D, E, F, G, H, I, J>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>, _ h: SignalProducer<H, Error>, _ i: SignalProducer<I, Error>, _ j: SignalProducer<J, Error>) -> SignalProducer<(Value, B, C, D, E, F, G, H, I, J), Error> {
		return SignalProducer<(Value, B, C, D, E, F, G, H, I, J), Error> { observer, disposable in
			flattenStart(disposable, a, b, c, d, e, f, g, h, i, j) { Signal.combineLatest($0, $1, $2, $3, $4, $5, $6, $7, $8, $9).observe(observer) }
		}
	}

	/// Combines the values of all the given producers, in the manner described by
	/// `combineLatest(with:)`. Will return an empty `SignalProducer` if the sequence is empty.
	public static func combineLatest<S: Sequence>(_ producers: S) -> SignalProducer<[Value], Error> where S.Iterator.Element == SignalProducer<Value, Error> {
		return start(producers, Signal.combineLatest)
	}

	/// Zips the values of all the given producers, in the manner described by
	/// `zip(with:)`.
	public static func zip<B>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>) -> SignalProducer<(Value, B), Error> {
		return SignalProducer<(Value, B), Error> { observer, disposable in
			flattenStart(disposable, a, b) { Signal.zip($0, $1).observe(observer) }
		}
	}

	/// Zips the values of all the given producers, in the manner described by
	/// `zip(with:)`.
	public static func zip<B, C>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>) -> SignalProducer<(Value, B, C), Error> {
		return SignalProducer<(Value, B, C), Error> { observer, disposable in
			flattenStart(disposable, a, b, c) { Signal.zip($0, $1, $2).observe(observer) }
		}
	}

	/// Zips the values of all the given producers, in the manner described by
	/// `zip(with:)`.
	public static func zip<B, C, D>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>) -> SignalProducer<(Value, B, C, D), Error> {
		return SignalProducer<(Value, B, C, D), Error> { observer, disposable in
			flattenStart(disposable, a, b, c, d) { Signal.zip($0, $1, $2, $3).observe(observer) }
		}
	}

	/// Zips the values of all the given producers, in the manner described by
	/// `zip(with:)`.
	public static func zip<B, C, D, E>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>) -> SignalProducer<(Value, B, C, D, E), Error> {
		return SignalProducer<(Value, B, C, D, E), Error> { observer, disposable in
			flattenStart(disposable, a, b, c, d, e) { Signal.zip($0, $1, $2, $3, $4).observe(observer) }
		}
	}

	/// Zips the values of all the given producers, in the manner described by
	/// `zip(with:)`.
	public static func zip<B, C, D, E, F>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>) -> SignalProducer<(Value, B, C, D, E, F), Error> {
		return SignalProducer<(Value, B, C, D, E, F), Error> { observer, disposable in
			flattenStart(disposable, a, b, c, d, e, f) { Signal.zip($0, $1, $2, $3, $4, $5).observe(observer) }
		}
	}

	/// Zips the values of all the given producers, in the manner described by
	/// `zip(with:)`.
	public static func zip<B, C, D, E, F, G>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>) -> SignalProducer<(Value, B, C, D, E, F, G), Error> {
		return SignalProducer<(Value, B, C, D, E, F, G), Error> { observer, disposable in
			flattenStart(disposable, a, b, c, d, e, f, g) { Signal.zip($0, $1, $2, $3, $4, $5, $6).observe(observer) }
		}
	}

	/// Zips the values of all the given producers, in the manner described by
	/// `zip(with:)`.
	public static func zip<B, C, D, E, F, G, H>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>, _ h: SignalProducer<H, Error>) -> SignalProducer<(Value, B, C, D, E, F, G, H), Error> {
		return SignalProducer<(Value, B, C, D, E, F, G, H), Error> { observer, disposable in
			flattenStart(disposable, a, b, c, d, e, f, g, h) { Signal.zip($0, $1, $2, $3, $4, $5, $6, $7).observe(observer) }
		}
	}

	/// Zips the values of all the given producers, in the manner described by
	/// `zip(with:)`.
	public static func zip<B, C, D, E, F, G, H, I>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>, _ h: SignalProducer<H, Error>, _ i: SignalProducer<I, Error>) -> SignalProducer<(Value, B, C, D, E, F, G, H, I), Error> {
		return SignalProducer<(Value, B, C, D, E, F, G, H, I), Error> { observer, disposable in
			flattenStart(disposable, a, b, c, d, e, f, g, h, i) { Signal.zip($0, $1, $2, $3, $4, $5, $6, $7, $8).observe(observer) }
		}
	}

	/// Zips the values of all the given producers, in the manner described by
	/// `zip(with:)`.
	public static func zip<B, C, D, E, F, G, H, I, J>(_ a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>, _ h: SignalProducer<H, Error>, _ i: SignalProducer<I, Error>, _ j: SignalProducer<J, Error>) -> SignalProducer<(Value, B, C, D, E, F, G, H, I, J), Error> {
		return SignalProducer<(Value, B, C, D, E, F, G, H, I, J), Error> { observer, disposable in
			flattenStart(disposable, a, b, c, d, e, f, g, h, i, j) { Signal.zip($0, $1, $2, $3, $4, $5, $6, $7, $8, $9).observe(observer) }
		}
	}

	/// Zips the values of all the given producers, in the manner described by
	/// `zipWith`. Will return an empty `SignalProducer` if the sequence is empty.
	public static func zip<S: Sequence>(_ producers: S) -> SignalProducer<[Value], Error> where S.Iterator.Element == SignalProducer<Value, Error> {
		return start(producers, Signal.zip)
	}

	private static func start<S: Sequence>(_ producers: S, _ transform: @escaping (ReversedRandomAccessCollection<[Signal<Value, Error>]>) -> Signal<[Value], Error>) -> SignalProducer<[Value], Error> where S.Iterator.Element == SignalProducer<Value, Error> {
		return SignalProducer<[Value], Error> { observer, disposable in
			var producers = Array(producers)
			var signals: [Signal<Value, Error>] = []

			guard !producers.isEmpty else {
				observer.sendCompleted()
				return
			}

			func start() {
				guard !producers.isEmpty else {
					transform(signals.reversed()).observe(observer)
					return
				}

				producers.removeLast().startWithSignal { signal, interruptHandle in
					disposable += interruptHandle
					signals.append(signal)

					start()
				}
			}
			
			start()
		}
	}
}

extension SignalProducer where Value == Bool {
	/// Create a producer that computes a logical NOT in the latest values of `self`.
	///
	/// - returns: A producer that emits the logical NOT results.
	public func negate() -> SignalProducer<Value, Error> {
		return self.lift { $0.negate() }
	}

	/// Create a producer that computes a logical AND between the latest values of `self`
	/// and `producer`.
	///
	/// - parameters:
	///   - producer: Producer to be combined with `self`.
	///
	/// - returns: A producer that emits the logical AND results.
	public func and(_ producer: SignalProducer<Value, Error>) -> SignalProducer<Value, Error> {
		return self.liftLeft(Signal.and)(producer)
	}

	/// Create a producer that computes a logical AND between the latest values of `self`
	/// and `signal`.
	///
	/// - parameters:
	///   - signal: Signal to be combined with `self`.
	///
	/// - returns: A producer that emits the logical AND results.
	public func and(_ signal: Signal<Value, Error>) -> SignalProducer<Value, Error> {
		return self.lift(Signal.and)(signal)
	}

	/// Create a producer that computes a logical OR between the latest values of `self`
	/// and `producer`.
	///
	/// - parameters:
	///   - producer: Producer to be combined with `self`.
	///
	/// - returns: A producer that emits the logical OR results.
	public func or(_ producer: SignalProducer<Value, Error>) -> SignalProducer<Value, Error> {
		return self.liftLeft(Signal.or)(producer)
	}

	/// Create a producer that computes a logical OR between the latest values of `self`
	/// and `signal`.
	///
	/// - parameters:
	///   - signal: Signal to be combined with `self`.
	///
	/// - returns: A producer that emits the logical OR results.
	public func or(_ signal: Signal<Value, Error>) -> SignalProducer<Value, Error> {
		return self.lift(Signal.or)(signal)
	}
}
