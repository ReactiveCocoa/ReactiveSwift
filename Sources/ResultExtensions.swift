import Result

extension Result: SignalProducerConvertible {
	public var producer: SignalProducer<Value, Error> {
		return .init(result: self)
	}
}
