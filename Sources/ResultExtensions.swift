import Result

extension Result: SignalProducerConvertible {
	public var producer: SignalProducer<Success, Failure> {
		return .init(result: self)
	}
}
