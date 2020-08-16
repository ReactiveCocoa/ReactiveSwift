open class Subscriber<Value, Error: Swift.Error>: _Subscriber {
	public init() {}

	open func receive(_ value: Value) { fatalError() }
	open func terminate(_ termination: Termination<Error>) { fatalError() }
}

extension Subscriber {
	internal func assumeUnboundDemand() -> Signal<Value, Error>.Observer {
		Signal.Observer(self.process)
	}
}

public enum Termination<Error: Swift.Error> {
	case failed(Error)
	case completed
	case interrupted
}

protocol _Subscriber {
	associatedtype Value
	associatedtype Error: Swift.Error

	func receive(_ value: Value)
	func terminate(_ termination: Termination<Error>)
}

extension _Subscriber {
	@available(*, deprecated, message:"Use named methods.")
	internal func callAsFunction(_ event: Signal<Value, Error>.Event) {
		process(event)
	}

	fileprivate func process(_ event: Signal<Value, Error>.Event) {
		switch event {
		case let .value(value):
			receive(value)
		case let .failed(error):
			terminate(.failed(error))
		case .completed:
			terminate(.completed)
		case .interrupted:
			terminate(.interrupted)
		}
	}

	@available(*, deprecated, renamed:"receive(_:)")
	internal func send(value: Value) {
		receive(value)
	}

	@available(*, deprecated, message:"terminate(.failed(error))")
	internal func send(error: Error) {
		terminate(.failed(error))
	}

	@available(*, deprecated, message:"terminate(.completed)")
	internal func sendCompleted() {
		terminate(.completed)
	}

	@available(*, deprecated, message:"terminate(.interrupted)")
	internal func sendInterrupted() {
		terminate(.interrupted)
	}
}
