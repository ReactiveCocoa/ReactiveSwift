//
//  Flatten.swift
//  ReactiveSwift
//
//  Created by Neil Pankey on 11/30/15.
//  Copyright © 2015 GitHub. All rights reserved.
//

import enum Result.NoError

/// Describes how multiple producers should be joined together.
public enum FlattenStrategy: Equatable {
	/// The producers should be merged, so that any value received on any of the
	/// input producers will be forwarded immediately to the output producer.
	///
	/// The resulting producer will complete only when all inputs have
	/// completed.
	public static let merge = FlattenStrategy.concurrent(limit: .max)

	/// The producers should be concatenated, so that their values are sent in
	/// the order of the producers themselves.
	///
	/// The resulting producer will complete only when all inputs have
	/// completed.
	public static let concat = FlattenStrategy.concurrent(limit: 1)

	/// The producers should be merged, but only up to the given limit at any
	/// point of time, so that any value received on any of the input producers
	/// will be forwarded immediately to the output producer.
	///
	/// When the number of active producers reaches the limit, subsequent
	/// producers are queued.
	///
	/// The resulting producer will complete only when all inputs have
	/// completed.
	case concurrent(limit: UInt)

	/// Only the events from the latest input producer should be considered for
	/// the output. Any producers received before that point will be disposed
	/// of.
	///
	/// The resulting producer will complete only when the producer-of-producers
	/// and the latest producer has completed.
	case latest

	public static func ==(left: FlattenStrategy, right: FlattenStrategy) -> Bool {
		switch (left, right) {
		case (.latest, .latest):
			return true

		case (.concurrent(let leftLimit), .concurrent(let rightLimit)):
			return leftLimit == rightLimit

		default:
			return false
		}
	}
}

extension SignalProtocol where Value: SignalProducerProtocol, Error == Value.Error {
	/// Flattens the inner producers sent upon `signal` (into a single signal of
	/// values), according to the semantics of the given strategy.
	///
	/// - note: If `signal` or an active inner producer fails, the returned
	///         signal will forward that failure immediately.
	///
	/// - note: `interrupted` events on inner producers will be treated like
	///         `Completed events on inner producers.
	public func flatten(_ strategy: FlattenStrategy) -> Signal<Value.Value, Error> {
		switch strategy {
		case .concurrent(let limit):
			return self.concurrent(limit: limit)

		case .latest:
			return self.switchToLatest()
		}
	}
}

extension SignalProtocol where Value: SignalProducerProtocol, Error == NoError {
	/// Flattens the inner producers sent upon `signal` (into a single signal of
	/// values), according to the semantics of the given strategy.
	///
	/// - note: If an active inner producer fails, the returned signal will
	///         forward that failure immediately.
	///
	/// - warning: `interrupted` events on inner producers will be treated like
	///            `completed` events on inner producers.
	///
	/// - parameters:
	///	  - strategy: Strategy used when flattening signals.
	public func flatten(_ strategy: FlattenStrategy) -> Signal<Value.Value, Value.Error> {
		return self
			.promoteErrors(Value.Error.self)
			.flatten(strategy)
	}
}

extension SignalProtocol where Value: SignalProducerProtocol, Error == NoError, Value.Error == NoError {
	/// Flattens the inner producers sent upon `signal` (into a single signal of
	/// values), according to the semantics of the given strategy.
	///
	/// - warning: `interrupted` events on inner producers will be treated like
	///            `completed` events on inner producers.
	///
	/// - parameters:
	///   - strategy: Strategy used when flattening signals.
	public func flatten(_ strategy: FlattenStrategy) -> Signal<Value.Value, Value.Error> {
		switch strategy {
		case .concurrent(let limit):
			return self.concurrent(limit: limit)

		case .latest:
			return self.switchToLatest()
		}
	}
}

extension SignalProtocol where Value: SignalProducerProtocol, Value.Error == NoError {
	/// Flattens the inner producers sent upon `signal` (into a single signal of
	/// values), according to the semantics of the given strategy.
	///
	/// - note: If `signal` fails, the returned signal will forward that failure
	///         immediately.
	///
	/// - warning: `interrupted` events on inner producers will be treated like
	///            `completed` events on inner producers.
	public func flatten(_ strategy: FlattenStrategy) -> Signal<Value.Value, Error> {
		return self.flatMap(strategy) { $0.promoteErrors(Error.self) }
	}
}

extension SignalProducerProtocol where Value: SignalProducerProtocol, Error == Value.Error {
	/// Flattens the inner producers sent upon `producer` (into a single
	/// producer of values), according to the semantics of the given strategy.
	///
	/// - note: If `producer` or an active inner producer fails, the returned
	///         producer will forward that failure immediately.
	///
	/// - warning: `interrupted` events on inner producers will be treated like
	///            `completed` events on inner producers.
	public func flatten(_ strategy: FlattenStrategy) -> SignalProducer<Value.Value, Error> {
		switch strategy {
		case .concurrent(let limit):
			return self.concurrent(limit: limit)

		case .latest:
			return self.switchToLatest()
		}
	}
}

extension SignalProducerProtocol where Value: SignalProducerProtocol, Error == NoError {
	/// Flattens the inner producers sent upon `producer` (into a single
	/// producer of values), according to the semantics of the given strategy.
	///
	/// - note: If an active inner producer fails, the returned producer will
	///         forward that failure immediately.
	///
	/// - warning: `interrupted` events on inner producers will be treated like
	///            `completed` events on inner producers.
	public func flatten(_ strategy: FlattenStrategy) -> SignalProducer<Value.Value, Value.Error> {
		return self
			.promoteErrors(Value.Error.self)
			.flatten(strategy)
	}
}

extension SignalProducerProtocol where Value: SignalProducerProtocol, Error == NoError, Value.Error == NoError {
	/// Flattens the inner producers sent upon `producer` (into a single
	/// producer of values), according to the semantics of the given strategy.
	///
	/// - warning: `interrupted` events on inner producers will be treated like
	///            `completed` events on inner producers.
	public func flatten(_ strategy: FlattenStrategy) -> SignalProducer<Value.Value, Value.Error> {
		switch strategy {
		case .concurrent(let limit):
			return self.concurrent(limit: limit)

		case .latest:
			return self.switchToLatest()
		}
	}
}

extension SignalProducerProtocol where Value: SignalProducerProtocol, Value.Error == NoError {
	/// Flattens the inner producers sent upon `signal` (into a single signal of
	/// values), according to the semantics of the given strategy.
	///
	/// - note: If `signal` fails, the returned signal will forward that failure
	///         immediately.
	///
	/// - warning: `interrupted` events on inner producers will be treated like
	///            `completed` events on inner producers.
	public func flatten(_ strategy: FlattenStrategy) -> SignalProducer<Value.Value, Error> {
		return self.flatMap(strategy) { $0.promoteErrors(Error.self) }
	}
}

extension SignalProtocol where Value: SignalProtocol, Error == Value.Error {
	/// Flattens the inner signals sent upon `signal` (into a single signal of
	/// values), according to the semantics of the given strategy.
	///
	/// - note: If `signal` or an active inner signal emits an error, the
	///         returned signal will forward that error immediately.
	///
	/// - warning: `interrupted` events on inner signals will be treated like
	///            `completed` events on inner signals.
	public func flatten(_ strategy: FlattenStrategy) -> Signal<Value.Value, Error> {
		return self
			.map(SignalProducer.init)
			.flatten(strategy)
	}
}

extension SignalProtocol where Value: SignalProtocol, Error == NoError {
	/// Flattens the inner signals sent upon `signal` (into a single signal of
	/// values), according to the semantics of the given strategy.
	///
	/// - note: If an active inner signal emits an error, the returned signal
	///         will forward that error immediately.
	///
	/// - warning: `interrupted` events on inner signals will be treated like
	///            `completed` events on inner signals.
	public func flatten(_ strategy: FlattenStrategy) -> Signal<Value.Value, Value.Error> {
		return self
			.promoteErrors(Value.Error.self)
			.flatten(strategy)
	}
}

extension SignalProtocol where Value: SignalProtocol, Error == NoError, Value.Error == NoError {
	/// Flattens the inner signals sent upon `signal` (into a single signal of
	/// values), according to the semantics of the given strategy.
	///
	/// - warning: `interrupted` events on inner signals will be treated like
	///            `completed` events on inner signals.
	public func flatten(_ strategy: FlattenStrategy) -> Signal<Value.Value, Value.Error> {
		return self
			.map(SignalProducer.init)
			.flatten(strategy)
	}
}

extension SignalProtocol where Value: SignalProtocol, Value.Error == NoError {
	/// Flattens the inner signals sent upon `signal` (into a single signal of
	/// values), according to the semantics of the given strategy.
	///
	/// - note: If `signal` emits an error, the returned signal will forward
	///         that error immediately.
	///
	/// - warning: `interrupted` events on inner signals will be treated like
	///            `completed` events on inner signals.
	public func flatten(_ strategy: FlattenStrategy) -> Signal<Value.Value, Error> {
		return self.flatMap(strategy) { $0.promoteErrors(Error.self) }
	}
}

extension SignalProtocol where Value: Sequence {
	/// Flattens the `sequence` value sent by `signal`.
	public func flatten() -> Signal<Value.Iterator.Element, Error> {
		return self.flatMap(.merge, transform: SignalProducer.init)
	}
}

extension SignalProducerProtocol where Value: SignalProtocol, Error == Value.Error {
	/// Flattens the inner signals sent upon `producer` (into a single producer
	/// of values), according to the semantics of the given strategy.
	///
	/// - note: If `producer` or an active inner signal emits an error, the
	///         returned producer will forward that error immediately.
	///
	/// - warning: `interrupted` events on inner signals will be treated like
	///            `completed` events on inner signals.
	public func flatten(_ strategy: FlattenStrategy) -> SignalProducer<Value.Value, Error> {
		return self
			.map(SignalProducer.init)
			.flatten(strategy)
	}
}

extension SignalProducerProtocol where Value: SignalProtocol, Error == NoError {
	/// Flattens the inner signals sent upon `producer` (into a single producer
	/// of values), according to the semantics of the given strategy.
	///
	/// - note: If an active inner signal emits an error, the returned producer
	///         will forward that error immediately.
	///
	/// - warning: `interrupted` events on inner signals will be treated like
	///            `completed` events on inner signals.
	public func flatten(_ strategy: FlattenStrategy) -> SignalProducer<Value.Value, Value.Error> {
		return self
			.promoteErrors(Value.Error.self)
			.flatten(strategy)
	}
}

extension SignalProducerProtocol where Value: SignalProtocol, Error == NoError, Value.Error == NoError {
	/// Flattens the inner signals sent upon `producer` (into a single producer
	/// of values), according to the semantics of the given strategy.
	///
	/// - warning: `interrupted` events on inner signals will be treated like
	///            `completed` events on inner signals.
	public func flatten(_ strategy: FlattenStrategy) -> SignalProducer<Value.Value, Value.Error> {
		return self
			.map(SignalProducer.init)
			.flatten(strategy)
	}
}

extension SignalProducerProtocol where Value: SignalProtocol, Value.Error == NoError {
	/// Flattens the inner signals sent upon `producer` (into a single producer
	/// of values), according to the semantics of the given strategy.
	///
	/// - note: If `producer` emits an error, the returned producer will forward
	///         that error immediately.
	///
	/// - warning: `interrupted` events on inner signals will be treated like
	///            `completed` events on inner signals.
	public func flatten(_ strategy: FlattenStrategy) -> SignalProducer<Value.Value, Error> {
		return self.flatMap(strategy) { $0.promoteErrors(Error.self) }
	}
}

extension SignalProducerProtocol where Value: Sequence {
	/// Flattens the `sequence` value sent by `signal`.
	public func flatten() -> SignalProducer<Value.Iterator.Element, Error> {
		return self.flatMap(.merge, transform: SignalProducer.init)
	}
}

extension SignalProtocol where Value: PropertyProtocol {
	/// Flattens the inner properties sent upon `signal` (into a single signal of
	/// values), according to the semantics of the given strategy.
	///
	/// - note: If `signal` fails, the returned signal will forward that failure
	///         immediately.
	public func flatten(_ strategy: FlattenStrategy) -> Signal<Value.Value, Error> {
		return self.flatMap(strategy) { $0.producer }
	}
}

extension SignalProducerProtocol where Value: PropertyProtocol {
	/// Flattens the inner properties sent upon `signal` (into a single signal of
	/// values), according to the semantics of the given strategy.
	///
	/// - note: If `signal` fails, the returned signal will forward that failure
	///         immediately.
	public func flatten(_ strategy: FlattenStrategy) -> SignalProducer<Value.Value, Error> {
		return self.flatMap(strategy) { $0.producer }
	}
}

extension SignalProtocol where Value: SignalProducerProtocol, Error == Value.Error {
	fileprivate func concurrent(limit: UInt) -> Signal<Value.Value, Error> {
		return Signal<Value.Value, Error> { relayObserver in
			let disposable = CompositeDisposable()
			let relayDisposable = CompositeDisposable()

			disposable += relayDisposable
			disposable += self.observeConcurrent(relayObserver, limit, relayDisposable)

			return disposable
		}
	}

	fileprivate func observeConcurrent(_ observer: Observer<Value.Value, Error>, _ limit: UInt, _ disposable: CompositeDisposable) -> Disposable? {
		let state = Atomic(ConcurrentFlattenState<Value.Value, Error>(limit: limit))

		func startNextIfNeeded() {
			while let producer = state.modify({ $0.dequeue() }) {
				let producerState = UnsafeAtomicState<ProducerState>(.starting)
				let cleanup = ScopedDisposable(ActionDisposable(action: producerState.deinitialize))

				producer.startWithSignal { signal, inner in
					let handle = disposable.add(inner)

					signal.observe { [cleanup] event in
						switch event {
						case .completed, .interrupted:
							handle.remove()
							_ = cleanup

							let shouldComplete: Bool = state.modify { state in
								state.activeCount -= 1
								return state.shouldComplete
							}

							if shouldComplete {
								observer.sendCompleted()
							} else if producerState.is(.started) {
								startNextIfNeeded()
							}

						case .value, .failed:
							observer.action(event)
						}
					}
				}

				producerState.setStarted()
			}
		}

		return observe { event in
			switch event {
			case let .value(value):
				state.modify { $0.queue.append(value.producer) }
				startNextIfNeeded()

			case let .failed(error):
				observer.send(error: error)

			case .completed:
				let shouldComplete: Bool = state.modify { state in
					state.isOuterCompleted = true
					return state.shouldComplete
				}

				if shouldComplete {
					observer.sendCompleted()
				}

			case .interrupted:
				observer.sendInterrupted()
			}
		}
	}
}

extension SignalProducerProtocol where Value: SignalProducerProtocol, Error == Value.Error {
	fileprivate func concurrent(limit: UInt) -> SignalProducer<Value.Value, Error> {
		return SignalProducer<Value.Value, Error> { relayObserver, disposable in
			self.startWithSignal { signal, signalDisposable in
				disposable += signalDisposable

				_ = signal.observeConcurrent(relayObserver, limit, disposable)
			}
		}
	}
}

extension SignalProducerProtocol {
	/// `concat`s `next` onto `self`.
	public func concat(_ next: SignalProducer<Value, Error>) -> SignalProducer<Value, Error> {
		return SignalProducer<SignalProducer<Value, Error>, Error>([ self.producer, next ]).flatten(.concat)
	}
	
	/// `concat`s `value` onto `self`.
	public func concat(value: Value) -> SignalProducer<Value, Error> {
		return self.concat(SignalProducer(value: value))
	}
	
	/// `concat`s `self` onto initial `previous`.
	public func prefix<P: SignalProducerProtocol>(_ previous: P) -> SignalProducer<Value, Error>
		where P.Value == Value, P.Error == Error
	{
		return previous.concat(self.producer)
	}
	
	/// `concat`s `self` onto initial `value`.
	public func prefix(value: Value) -> SignalProducer<Value, Error> {
		return self.prefix(SignalProducer(value: value))
	}
}

private final class ConcurrentFlattenState<Value, Error: Swift.Error> {
	typealias Producer = ReactiveSwift.SignalProducer<Value, Error>

	/// The limit of active producers.
	let limit: UInt
	
	/// The number of active producers.
	var activeCount: UInt = 0
	
	/// The producers waiting to be started.
	var queue: [Producer] = []

	/// Whether the outer producer has completed.
	var isOuterCompleted = false

	/// Whether the flattened signal should complete.
	var shouldComplete: Bool {
		return isOuterCompleted && activeCount == 0 && queue.isEmpty
	}

	init(limit: UInt) {
		self.limit = limit
	}
	
	/// Dequeue the next producer if one should be started.
	///
	/// - returns: The `Producer` to start or `nil` if no producer should be
	///            started.
	func dequeue() -> Producer? {
		if activeCount < limit, !queue.isEmpty {
			activeCount += 1
			return queue.removeFirst()
		} else {
			return nil
		}
	}
}

private enum ProducerState: Int32 {
	case starting
	case started
}

extension AtomicStateProtocol where State == ProducerState {
	fileprivate func setStarted() {
		precondition(tryTransition(from: .starting, to: .started), "The transition is not supposed to fail.")
	}
}

extension SignalProtocol {
	/// Merges the given signals into a single `Signal` that will emit all
	/// values from each of them, and complete when all of them have completed.
	public static func merge<Seq: Sequence, S: SignalProtocol>(_ signals: Seq) -> Signal<Value, Error>
		where S.Value == Value, S.Error == Error, Seq.Iterator.Element == S
	{
		return SignalProducer<S, Error>(signals)
			.flatten(.merge)
			.startAndRetrieveSignal()
	}
	
	/// Merges the given signals into a single `Signal` that will emit all
	/// values from each of them, and complete when all of them have completed.
	public static func merge<S: SignalProtocol>(_ signals: S...) -> Signal<Value, Error>
		where S.Value == Value, S.Error == Error
	{
		return Signal.merge(signals)
	}
}

extension SignalProducerProtocol {
	/// Merges the given producers into a single `SignalProducer` that will emit
	/// all values from each of them, and complete when all of them have
	/// completed.
	public static func merge<Seq: Sequence, S: SignalProducerProtocol>(_ producers: Seq) -> SignalProducer<Value, Error>
		where S.Value == Value, S.Error == Error, Seq.Iterator.Element == S
	{
		return SignalProducer(producers).flatten(.merge)
	}
	
	/// Merges the given producers into a single `SignalProducer` that will emit
	/// all values from each of them, and complete when all of them have
	/// completed.
	public static func merge<S: SignalProducerProtocol>(_ producers: S...) -> SignalProducer<Value, Error>
		where S.Value == Value, S.Error == Error
	{
		return SignalProducer.merge(producers)
	}
}

extension SignalProtocol where Value: SignalProducerProtocol, Error == Value.Error {
	/// Returns a signal that forwards values from the latest signal sent on
	/// `signal`, ignoring values sent on previous inner signal.
	///
	/// An error sent on `signal` or the latest inner signal will be sent on the
	/// returned signal.
	///
	/// The returned signal completes when `signal` and the latest inner
	/// signal have both completed.
	fileprivate func switchToLatest() -> Signal<Value.Value, Error> {
		return Signal<Value.Value, Error> { observer in
			let composite = CompositeDisposable()
			let serial = SerialDisposable()

			composite += serial
			composite += self.observeSwitchToLatest(observer, serial)

			return composite
		}
	}

	fileprivate func observeSwitchToLatest(_ observer: Observer<Value.Value, Error>, _ latestInnerDisposable: SerialDisposable) -> Disposable? {
		let state = Atomic(LatestState<Value, Error>())

		return self.observe { event in
			switch event {
			case let .value(innerProducer):
				innerProducer.startWithSignal { innerSignal, innerDisposable in
					state.modify {
						// When we replace the disposable below, this prevents
						// the generated Interrupted event from doing any work.
						$0.replacingInnerSignal = true
					}

					latestInnerDisposable.inner = innerDisposable

					state.modify {
						$0.replacingInnerSignal = false
						$0.innerSignalComplete = false
					}

					innerSignal.observe { event in
						switch event {
						case .interrupted:
							// If interruption occurred as a result of a new
							// producer arriving, we don't want to notify our
							// observer.
							let shouldComplete: Bool = state.modify { state in
								if !state.replacingInnerSignal {
									state.innerSignalComplete = true
								}
								return !state.replacingInnerSignal && state.outerSignalComplete
							}

							if shouldComplete {
								observer.sendCompleted()
							}

						case .completed:
							let shouldComplete: Bool = state.modify {
								$0.innerSignalComplete = true
								return $0.outerSignalComplete
							}

							if shouldComplete {
								observer.sendCompleted()
							}

						case .value, .failed:
							observer.action(event)
						}
					}
				}

			case let .failed(error):
				observer.send(error: error)

			case .completed:
				let shouldComplete: Bool = state.modify {
					$0.outerSignalComplete = true
					return $0.innerSignalComplete
				}

				if shouldComplete {
					observer.sendCompleted()
				}

			case .interrupted:
				observer.sendInterrupted()
			}
		}
	}
}

extension SignalProducerProtocol where Value: SignalProducerProtocol, Error == Value.Error {
	/// Returns a signal that forwards values from the latest signal sent on
	/// `signal`, ignoring values sent on previous inner signal.
	///
	/// An error sent on `signal` or the latest inner signal will be sent on the
	/// returned signal.
	///
	/// The returned signal completes when `signal` and the latest inner
	/// signal have both completed.
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
}

private struct LatestState<Value, Error: Swift.Error> {
	var outerSignalComplete: Bool = false
	var innerSignalComplete: Bool = true
	
	var replacingInnerSignal: Bool = false
}


extension SignalProtocol {
	/// Maps each event from `signal` to a new signal, then flattens the
	/// resulting producers (into a signal of values), according to the
	/// semantics of the given strategy.
	///
	/// If `signal` or any of the created producers fail, the returned signal
	/// will forward that failure immediately.
	public func flatMap<U>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> SignalProducer<U, Error>) -> Signal<U, Error> {
		return map(transform).flatten(strategy)
	}
	
	/// Maps each event from `signal` to a new signal, then flattens the
	/// resulting producers (into a signal of values), according to the
	/// semantics of the given strategy.
	///
	/// If `signal` fails, the returned signal will forward that failure
	/// immediately.
	public func flatMap<U>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> SignalProducer<U, NoError>) -> Signal<U, Error> {
		return map(transform).flatten(strategy)
	}

	/// Maps each event from `signal` to a new signal, then flattens the
	/// resulting signals (into a signal of values), according to the
	/// semantics of the given strategy.
	///
	/// If `signal` or any of the created signals emit an error, the returned
	/// signal will forward that error immediately.
	public func flatMap<U>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> Signal<U, Error>) -> Signal<U, Error> {
		return map(transform).flatten(strategy)
	}

	/// Maps each event from `signal` to a new signal, then flattens the
	/// resulting signals (into a signal of values), according to the
	/// semantics of the given strategy.
	///
	/// If `signal` emits an error, the returned signal will forward that
	/// error immediately.
	public func flatMap<U>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> Signal<U, NoError>) -> Signal<U, Error> {
		return map(transform).flatten(strategy)
	}

	/// Maps each event from `signal` to a new property, then flattens the
	/// resulting properties (into a signal of values), according to the
	/// semantics of the given strategy.
	///
	/// If `signal` emits an error, the returned signal will forward that
	/// error immediately.
	public func flatMap<P: PropertyProtocol>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> P) -> Signal<P.Value, Error> {
		return map(transform).flatten(strategy)
	}
}

extension SignalProtocol where Error == NoError {
	/// Maps each event from `signal` to a new signal, then flattens the
	/// resulting signals (into a signal of values), according to the
	/// semantics of the given strategy.
	///
	/// If any of the created signals emit an error, the returned signal
	/// will forward that error immediately.
	public func flatMap<U, E>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> SignalProducer<U, E>) -> Signal<U, E> {
		return map(transform).flatten(strategy)
	}
	
	/// Maps each event from `signal` to a new signal, then flattens the
	/// resulting signals (into a signal of values), according to the
	/// semantics of the given strategy.
	public func flatMap<U>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> SignalProducer<U, NoError>) -> Signal<U, NoError> {
		return map(transform).flatten(strategy)
	}
	
	/// Maps each event from `signal` to a new signal, then flattens the
	/// resulting signals (into a signal of values), according to the
	/// semantics of the given strategy.
	///
	/// If any of the created signals emit an error, the returned signal
	/// will forward that error immediately.
	public func flatMap<U, E>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> Signal<U, E>) -> Signal<U, E> {
		return map(transform).flatten(strategy)
	}

	/// Maps each event from `signal` to a new signal, then flattens the
	/// resulting signals (into a signal of values), according to the
	/// semantics of the given strategy.
	public func flatMap<U>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> Signal<U, NoError>) -> Signal<U, NoError> {
		return map(transform).flatten(strategy)
	}
}

extension SignalProducerProtocol {
	/// Maps each event from `self` to a new producer, then flattens the
	/// resulting producers (into a producer of values), according to the
	/// semantics of the given strategy.
	///
	/// If `self` or any of the created producers fail, the returned producer
	/// will forward that failure immediately.
	public func flatMap<U>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> SignalProducer<U, Error>) -> SignalProducer<U, Error> {
		return map(transform).flatten(strategy)
	}
	
	/// Maps each event from `self` to a new producer, then flattens the
	/// resulting producers (into a producer of values), according to the
	/// semantics of the given strategy.
	///
	/// If `self` fails, the returned producer will forward that failure
	/// immediately.
	public func flatMap<U>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> SignalProducer<U, NoError>) -> SignalProducer<U, Error> {
		return map(transform).flatten(strategy)
	}

	/// Maps each event from `self` to a new producer, then flattens the
	/// resulting signals (into a producer of values), according to the
	/// semantics of the given strategy.
	///
	/// If `self` or any of the created signals emit an error, the returned
	/// producer will forward that error immediately.
	public func flatMap<U>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> Signal<U, Error>) -> SignalProducer<U, Error> {
		return map(transform).flatten(strategy)
	}

	/// Maps each event from `self` to a new producer, then flattens the
	/// resulting signals (into a producer of values), according to the
	/// semantics of the given strategy.
	///
	/// If `self` emits an error, the returned producer will forward that
	/// error immediately.
	public func flatMap<U>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> Signal<U, NoError>) -> SignalProducer<U, Error> {
		return map(transform).flatten(strategy)
	}

	/// Maps each event from `self` to a new property, then flattens the
	/// resulting properties (into a producer of values), according to the
	/// semantics of the given strategy.
	///
	/// If `self` emits an error, the returned producer will forward that
	/// error immediately.
	public func flatMap<P: PropertyProtocol>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> P) -> SignalProducer<P.Value, Error> {
		return map(transform).flatten(strategy)
	}
}

extension SignalProducerProtocol where Error == NoError {
	/// Maps each event from `self` to a new producer, then flattens the
	/// resulting producers (into a producer of values), according to the
	/// semantics of the given strategy.
	///
	/// If any of the created producers fail, the returned producer will
	/// forward that failure immediately.
	public func flatMap<U, E>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> SignalProducer<U, E>) -> SignalProducer<U, E> {
		return map(transform).flatten(strategy)
	}
	
	/// Maps each event from `self` to a new producer, then flattens the
	/// resulting producers (into a producer of values), according to the
	/// semantics of the given strategy.
	public func flatMap<U>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> SignalProducer<U, NoError>) -> SignalProducer<U, NoError> {
		return map(transform).flatten(strategy)
	}

	/// Maps each event from `self` to a new producer, then flattens the
	/// resulting signals (into a producer of values), according to the
	/// semantics of the given strategy.
	///
	/// If any of the created signals emit an error, the returned
	/// producer will forward that error immediately.
	public func flatMap<U, E>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> Signal<U, E>) -> SignalProducer<U, E> {
		return map(transform).flatten(strategy)
	}

	/// Maps each event from `self` to a new producer, then flattens the
	/// resulting signals (into a producer of values), according to the
	/// semantics of the given strategy.
	public func flatMap<U>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> Signal<U, NoError>) -> SignalProducer<U, NoError> {
		return map(transform).flatten(strategy)
	}
}


extension SignalProtocol {
	/// Catches any failure that may occur on the input signal, mapping to a new
	/// producer that starts in its place.
	public func flatMapError<F>(_ handler: @escaping (Error) -> SignalProducer<Value, F>) -> Signal<Value, F> {
		return Signal { observer in
			self.observeFlatMapError(handler, observer, SerialDisposable())
		}
	}

	fileprivate func observeFlatMapError<F>(_ handler: @escaping (Error) -> SignalProducer<Value, F>, _ observer: Observer<Value, F>, _ serialDisposable: SerialDisposable) -> Disposable? {
		return self.observe { event in
			switch event {
			case let .value(value):
				observer.send(value: value)
			case let .failed(error):
				handler(error).startWithSignal { signal, disposable in
					serialDisposable.inner = disposable
					signal.observe(observer)
				}
			case .completed:
				observer.sendCompleted()
			case .interrupted:
				observer.sendInterrupted()
			}
		}
	}
}

extension SignalProducerProtocol {
	/// Catches any failure that may occur on the input producer, mapping to a
	/// new producer that starts in its place.
	public func flatMapError<F>(_ handler: @escaping (Error) -> SignalProducer<Value, F>) -> SignalProducer<Value, F> {
		return SignalProducer { observer, disposable in
			let serialDisposable = SerialDisposable()
			disposable += serialDisposable

			self.startWithSignal { signal, signalDisposable in
				serialDisposable.inner = signalDisposable

				_ = signal.observeFlatMapError(handler, observer, serialDisposable)
			}
		}
	}
}
