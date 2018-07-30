import Result

public struct Promise<Value, Error: Swift.Error> {
	/// `Promise` is implemented as a thin wrapper around `SignalProducer`,
	/// providing stronger compile-time guarantees by internalizing all the
	/// necessary runtime assumptions.
	private let base: SignalProducer<Value, Error>

	private init(base: SignalProducer<Value, Error>) {
		self.base = base
	}

	public init<Other: SignalProducerConvertible>(_ other: Other) where Other.Value == Value, Other.Error == Error {
		base = other.producer.take(last: 1)
	}

	public init(value: Value) {
		base = .init(value: value)
	}

	public init(error: Error) {
		base = .init(error: error)
	}
}

extension Promise {
	public enum Event {
		case completed(Value)
		case failed(Error)
		case interrupted
	}
}

extension Signal.Event {
	fileprivate func apply(to action: @escaping (Promise<Value, Error>.Event) -> Void) {
		switch self {
		case let .value(value):
			action(.completed(value))
		case let .failed(error):
			action(.failed(error))
		case .interrupted:
			action(.interrupted)
		case .completed:
			break
		}
	}
}

extension Promise {
	public func start(_ action: @escaping (Event) -> Void) -> Disposable {
		return base.start { $0.apply(to: action) }
	}

	public func startWithFailed(_ action: @escaping (Error) -> Void) -> Disposable {
		return base.startWithFailed(action)
	}

	public func startWithResult(_ action: @escaping (Result<Value, Error>) -> Void) -> Disposable {
		return base.startWithResult(action)
	}
}

extension Promise where Error == NoError {
	public func startWithCompleted(_ action: @escaping (Value) -> Void) -> Disposable {
		return base.startWithValues(action)
	}
}

extension Promise {
	public func lift<U, E>(_ transform: (SignalProducer<Value, Error>) -> SignalProducer<U, E>) -> Promise<U, E> {
		return unguardedLift { transform($0).take(last: 1) }
	}

	private func unguardedLift<U, E>(_ transform: (SignalProducer<Value, Error>) -> SignalProducer<U, E>) -> Promise<U, E> {
		return Promise<U, E>(base: transform(base))
	}

	public func map<U>(_ transform: @escaping (Value) -> U) -> Promise<U, Error> {
		return unguardedLift { $0.map(transform) }
	}

	public func mapError<E>(_ transform: @escaping (Error) -> E) -> Promise<Value, E> {
		return unguardedLift { $0.mapError(transform) }
	}

	public func observe(on scheduler: Scheduler) -> Promise<Value, Error> {
		return unguardedLift { $0.observe(on: scheduler) }
	}

	public func start(on scheduler: Scheduler) -> Promise<Value, Error> {
		return unguardedLift { $0.start(on: scheduler) }
	}

	public func replayLazily() -> Promise<Value, Error> {
		return unguardedLift { $0.replayLazily(upTo: 1) }
	}
}

extension Promise {
	public func zip<U>(with other: Promise<U, Error>) -> Promise<(Value, U), Error> {
		return unguardedLift { $0.zip(with: other.base) }
	}
}
