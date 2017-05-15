import enum Result.NoError

extension Signal {
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
}

private struct SampleState<Value> {
	var latestValue: Value? = nil
	var isSignalCompleted: Bool = false
	var isSamplerCompleted: Bool = false
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

extension Signal where Value == Bool {
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
