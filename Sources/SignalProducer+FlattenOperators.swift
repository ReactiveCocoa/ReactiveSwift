import enum Result.NoError

extension SignalProducer where Value: SignalProducerProtocol, Error == Value.Error {
	fileprivate func concurrent(limit: UInt) -> SignalProducer<Value.Value, Error> {
		precondition(limit > 0, "The concurrent limit must be greater than zero.")

		return SignalProducer<Value.Value, Error> { relayObserver, disposable in
			self.startWithSignal { signal, signalDisposable in
				disposable += signalDisposable

				_ = signal.observeConcurrent(relayObserver, limit, disposable)
			}
		}
	}

	/// - warning: An error sent on `signal` or the latest inner signal will be
	///            sent on the returned signal.
	///
	/// - note: The returned signal completes when `signal` and the latest inner
	///         signal have both completed.
	///
	/// - returns: A signal that forwards values from the latest signal sent on
	///            `signal`, ignoring values sent on previous inner signal.
	fileprivate func switchToLatest() -> SignalProducer<Value.Value, Error> {
		return SignalProducer<Value.Value, Error> { observer, disposable in
			let latestInnerDisposable = SerialDisposable()
			disposable += latestInnerDisposable

			self.startWithSignal { signal, signalDisposable in
				disposable += signalDisposable
				disposable += signal.observeSwitchToLatest(observer, latestInnerDisposable)
			}
		}
	}

	/// Returns a producer that forwards values from the "first input producer to send an event"
	/// (winning producer) that is sent on `self`, ignoring values sent from other inner producers.
	///
	/// An error sent on `self` or the winning inner producer will be sent on the
	/// returned producer.
	///
	/// The returned producer completes when `self` and the winning inner producer have both completed.
	fileprivate func race() -> SignalProducer<Value.Value, Error> {
		return SignalProducer<Value.Value, Error> { observer, disposable in
			let relayDisposable = CompositeDisposable()
			disposable += relayDisposable

			self.startWithSignal { signal, signalDisposable in
				disposable += signalDisposable
				disposable += signal.observeRace(observer, relayDisposable)
			}
		}
	}
}

extension SignalProducer where Value: SignalProducerProtocol, Error == Value.Error {
	/// Flattens the inner producers sent upon `producer` (into a single
	/// producer of values), according to the semantics of the given strategy.
	///
	/// - note: If `producer` or an active inner producer fails, the returned
	///         producer will forward that failure immediately.
	///
	/// - warning: `interrupted` events on inner producers will be treated like
	///            `completed` events on inner producers.
	///
	/// - parameters:
	///   - strategy: Strategy used when flattening signals.
	public func flatten(_ strategy: FlattenStrategy) -> SignalProducer<Value.Value, Error> {
		switch strategy {
		case .concurrent(let limit):
			return self.concurrent(limit: limit)

		case .latest:
			return self.switchToLatest()

		case .race:
			return self.race()
		}
	}
}

extension SignalProducer where Value: SignalProducerProtocol, Error == NoError {
	/// Flattens the inner producers sent upon `producer` (into a single
	/// producer of values), according to the semantics of the given strategy.
	///
	/// - note: If an active inner producer fails, the returned producer will
	///         forward that failure immediately.
	///
	/// - warning: `interrupted` events on inner producers will be treated like
	///            `completed` events on inner producers.
	///
	/// - parameters:
	///   - strategy: Strategy used when flattening signals.
	public func flatten(_ strategy: FlattenStrategy) -> SignalProducer<Value.Value, Value.Error> {
		return self
			.promoteErrors(Value.Error.self)
			.flatten(strategy)
	}
}

extension SignalProducer where Value: SignalProducerProtocol, Error == NoError, Value.Error == NoError {
	/// Flattens the inner producers sent upon `producer` (into a single
	/// producer of values), according to the semantics of the given strategy.
	///
	/// - warning: `interrupted` events on inner producers will be treated like
	///            `completed` events on inner producers.
	///
	/// - parameters:
	///   - strategy: Strategy used when flattening signals.
	public func flatten(_ strategy: FlattenStrategy) -> SignalProducer<Value.Value, Value.Error> {
		switch strategy {
		case .concurrent(let limit):
			return self.concurrent(limit: limit)

		case .latest:
			return self.switchToLatest()

		case .race:
			return self.race()
		}
	}
}

extension SignalProducer where Value: SignalProducerProtocol, Value.Error == NoError {
	/// Flattens the inner producers sent upon `signal` (into a single signal of
	/// values), according to the semantics of the given strategy.
	///
	/// - note: If `signal` fails, the returned signal will forward that failure
	///         immediately.
	///
	/// - warning: `interrupted` events on inner producers will be treated like
	///            `completed` events on inner producers.
	///
	/// - parameters:
	///   - strategy: Strategy used when flattening signals.
	public func flatten(_ strategy: FlattenStrategy) -> SignalProducer<Value.Value, Error> {
		return self.flatMap(strategy) { $0.producer.promoteErrors(Error.self) }
	}
}

extension SignalProducer where Value: SignalProtocol, Error == Value.Error {
	/// Flattens the inner signals sent upon `producer` (into a single producer
	/// of values), according to the semantics of the given strategy.
	///
	/// - note: If `producer` or an active inner signal emits an error, the
	///         returned producer will forward that error immediately.
	///
	/// - warning: `interrupted` events on inner signals will be treated like
	///            `completed` events on inner signals.
	///
	/// - parameters:
	///   - strategy: Strategy used when flattening signals.
	public func flatten(_ strategy: FlattenStrategy) -> SignalProducer<Value.Value, Error> {
		return self
			.map { SignalProducer<Value.Value, Value.Error>($0.signal) }
			.flatten(strategy)
	}
}

extension SignalProducer where Value: SignalProtocol, Error == NoError {
	/// Flattens the inner signals sent upon `producer` (into a single producer
	/// of values), according to the semantics of the given strategy.
	///
	/// - note: If an active inner signal emits an error, the returned producer
	///         will forward that error immediately.
	///
	/// - warning: `interrupted` events on inner signals will be treated like
	///            `completed` events on inner signals.
	///
	/// - parameters:
	///   - strategy: Strategy used when flattening signals.
	public func flatten(_ strategy: FlattenStrategy) -> SignalProducer<Value.Value, Value.Error> {
		return self
			.promoteErrors(Value.Error.self)
			.flatten(strategy)
	}
}

extension SignalProducer where Value: SignalProtocol, Error == NoError, Value.Error == NoError {
	/// Flattens the inner signals sent upon `producer` (into a single producer
	/// of values), according to the semantics of the given strategy.
	///
	/// - warning: `interrupted` events on inner signals will be treated like
	///            `completed` events on inner signals.
	///
	/// - parameters:
	///   - strategy: Strategy used when flattening signals.
	public func flatten(_ strategy: FlattenStrategy) -> SignalProducer<Value.Value, Value.Error> {
		return self
			.map { SignalProducer<Value.Value, NoError>($0.signal) }
			.flatten(strategy)
	}
}

extension SignalProducer where Value: SignalProtocol, Value.Error == NoError {
	/// Flattens the inner signals sent upon `producer` (into a single producer
	/// of values), according to the semantics of the given strategy.
	///
	/// - note: If `producer` emits an error, the returned producer will forward
	///         that error immediately.
	///
	/// - warning: `interrupted` events on inner signals will be treated like
	///            `completed` events on inner signals.
	///
	/// - parameters:
	///   - strategy: Strategy used when flattening signals.
	public func flatten(_ strategy: FlattenStrategy) -> SignalProducer<Value.Value, Error> {
		return self.flatMap(strategy) { $0.signal.promoteErrors(Error.self) }
	}
}

extension SignalProducer where Value: Sequence {
	/// Flattens the `sequence` value sent by `signal`.
	public func flatten() -> SignalProducer<Value.Iterator.Element, Error> {
		return self.flatMap(.merge, SignalProducer<Value.Iterator.Element, NoError>.init)
	}
}

extension SignalProducer where Value: PropertyProtocol {
	/// Flattens the inner properties sent upon `signal` (into a single signal of
	/// values), according to the semantics of the given strategy.
	///
	/// - note: If `signal` fails, the returned signal will forward that failure
	///         immediately.
	///
	/// - parameters:
	///   - strategy: Strategy used when flattening signals.
	public func flatten(_ strategy: FlattenStrategy) -> SignalProducer<Value.Value, Error> {
		return self.flatMap(strategy) { $0.producer }
	}
}

extension SignalProducer {
	/// `concat`s `next` onto `self`.
	///
	/// - parameters:
	///   - next: A follow-up producer to concat `self` with.
	///
	/// - returns: A producer that will start `self` and then on completion of
	///            `self` - will start `next`.
	public func concat(_ next: SignalProducer<Value, Error>) -> SignalProducer<Value, Error> {
		return SignalProducer<SignalProducer<Value, Error>, Error>([ self.producer, next ]).flatten(.concat)
	}

	/// `concat`s `value` onto `self`.
	///
	/// - parameters:
	///   - value: A value to concat onto `self`.
	///
	/// - returns: A producer that, when started, will emit own values and on
	///            completion will emit a `value`.
	public func concat(value: Value) -> SignalProducer<Value, Error> {
		return self.concat(SignalProducer(value: value))
	}

	/// `concat`s `self` onto initial `previous`.
	///
	/// - parameters:
	///   - previous: A producer to start before `self`.
	///
	/// - returns: A signal producer that, when started, first emits values from
	///            `previous` producer and then from `self`.
	public func prefix(_ previous: SignalProducer<Value, Error>) -> SignalProducer<Value, Error> {
		return previous.concat(self)
	}

	/// `concat`s `self` onto initial `value`.
	///
	/// - parameters:
	///   - value: A first value to emit.
	///
	/// - returns: A producer that, when started, first emits `value`, then all
	///            values emited by `self`.
	public func prefix(value: Value) -> SignalProducer<Value, Error> {
		return self.prefix(SignalProducer(value: value))
	}

	/// Merges the given producers into a single `SignalProducer` that will emit
	/// all values from each of them, and complete when all of them have
	/// completed.
	///
	/// - parameters:
	///   - producers: A sequence of producers to merge.
	public static func merge<Seq: Sequence>(_ producers: Seq) -> SignalProducer<Value, Error> where Seq.Iterator.Element == SignalProducer<Value, Error>
	{
		return SignalProducer<Seq.Iterator.Element, NoError>(producers).flatten(.merge)
	}

	/// Merges the given producers into a single `SignalProducer` that will emit
	/// all values from each of them, and complete when all of them have
	/// completed.
	///
	/// - parameters:
	///   - producers: A sequence of producers to merge.
	public static func merge(_ producers: SignalProducer<Value, Error>...) -> SignalProducer<Value, Error> {
		return SignalProducer.merge(producers)
	}

	/// Maps each event from `self` to a new producer, then flattens the
	/// resulting producers (into a producer of values), according to the
	/// semantics of the given strategy.
	///
	/// - warning: If `self` or any of the created producers fail, the returned
	///            producer will forward that failure immediately.
	///
	/// - parameters:
	///	  - strategy: Strategy used when flattening signals.
	///   - transform: A closure that takes a value emitted by `self` and
	///                returns a signal producer with transformed value.
	public func flatMap<U>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> SignalProducer<U, Error>) -> SignalProducer<U, Error> {
		return map(transform).flatten(strategy)
	}

	/// Maps each event from `self` to a new producer, then flattens the
	/// resulting producers (into a producer of values), according to the
	/// semantics of the given strategy.
	///
	/// - warning: If `self` fails, the returned producer will forward that
	///            failure immediately.
	///
	/// - parameters:
	///	  - strategy: Strategy used when flattening signals.
	///   - transform: A closure that takes a value emitted by `self` and
	///                returns a signal producer with transformed value.
	public func flatMap<U>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> SignalProducer<U, NoError>) -> SignalProducer<U, Error> {
		return map(transform).flatten(strategy)
	}

	/// Maps each event from `self` to a new producer, then flattens the
	/// resulting signals (into a producer of values), according to the
	/// semantics of the given strategy.
	///
	/// - warning: If `self` or any of the created signals emit an error, the
	///            returned producer will forward that error immediately.
	///
	/// - parameters:
	///	  - strategy: Strategy used when flattening signals.
	///   - transform: A closure that takes a value emitted by `self` and
	///                returns a signal with transformed value.
	public func flatMap<U>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Signal<U, Error>) -> SignalProducer<U, Error> {
		return map(transform).flatten(strategy)
	}

	/// Maps each event from `self` to a new producer, then flattens the
	/// resulting signals (into a producer of values), according to the
	/// semantics of the given strategy.
	///
	/// - warning: If `self` emits an error, the returned producer will forward
	///            that error immediately.
	///
	/// - parameters:
	///	  - strategy: Strategy used when flattening signals.
	///   - transform: A closure that takes a value emitted by `self` and
	///                returns a signal with transformed value.
	public func flatMap<U>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Signal<U, NoError>) -> SignalProducer<U, Error> {
		return map(transform).flatten(strategy)
	}

	/// Maps each event from `self` to a new property, then flattens the
	/// resulting properties (into a producer of values), according to the
	/// semantics of the given strategy.
	///
	/// - warning: If `self` emits an error, the returned producer will forward
	///            that error immediately.
	///
	/// - parameters:
	///	  - strategy: Strategy used when flattening signals.
	///   - transform: A closure that takes a value emitted by `self` and
	///                returns a property with transformed value.
	public func flatMap<P: PropertyProtocol>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> P) -> SignalProducer<P.Value, Error> {
		return map(transform).flatten(strategy)
	}
}

extension SignalProducer where Error == NoError {
	/// Maps each event from `self` to a new producer, then flattens the
	/// resulting producers (into a producer of values), according to the
	/// semantics of the given strategy.
	///
	/// - warning: If any of the created producers fail, the returned producer
	///            will forward that failure immediately.
	///
	/// - parameters:
	///	  - strategy: Strategy used when flattening signals.
	///   - transform: A closure that takes a value emitted by `self` and
	///                returns a signal producer with transformed value.
	public func flatMap<U, E>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> SignalProducer<U, E>) -> SignalProducer<U, E> {
		return map(transform).flatten(strategy)
	}

	/// Maps each event from `self` to a new producer, then flattens the
	/// resulting producers (into a producer of values), according to the
	/// semantics of the given strategy.
	///
	/// - parameters:
	///	  - strategy: Strategy used when flattening signals.
	///   - transform: A closure that takes a value emitted by `self` and
	///                returns a signal producer with transformed value.
	public func flatMap<U>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> SignalProducer<U, NoError>) -> SignalProducer<U, NoError> {
		return map(transform).flatten(strategy)
	}

	/// Maps each event from `self` to a new producer, then flattens the
	/// resulting signals (into a producer of values), according to the
	/// semantics of the given strategy.
	///
	/// - warning: If any of the created signals emit an error, the returned
	///            producer will forward that error immediately.
	///
	/// - parameters:
	///	  - strategy: Strategy used when flattening signals.
	///   - transform: A closure that takes a value emitted by `self` and
	///                returns a signal with transformed value.
	public func flatMap<U, E>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Signal<U, E>) -> SignalProducer<U, E> {
		return map(transform).flatten(strategy)
	}

	/// Maps each event from `self` to a new producer, then flattens the
	/// resulting signals (into a producer of values), according to the
	/// semantics of the given strategy.
	///
	/// - parameters:
	///	  - strategy: Strategy used when flattening signals.
	///   - transform: A closure that takes a value emitted by `self` and
	///                returns a signal with transformed value.
	public func flatMap<U>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Signal<U, NoError>) -> SignalProducer<U, NoError> {
		return map(transform).flatten(strategy)
	}
}

extension SignalProducer {
	/// Catches any failure that may occur on the input producer, mapping to a
	/// new producer that starts in its place.
	///
	/// - parameters:
	///   - transform: A closure that accepts emitted error and returns a signal
	///                producer with a different type of error.
	public func flatMapError<F>(_ transform: @escaping (Error) -> SignalProducer<Value, F>) -> SignalProducer<Value, F> {
		return SignalProducer<Value, F> { observer, disposable in
			let serialDisposable = SerialDisposable()
			disposable += serialDisposable

			self.startWithSignal { signal, signalDisposable in
				serialDisposable.inner = signalDisposable

				_ = signal.observeFlatMapError(transform, observer, serialDisposable)
			}
		}
	}
}
