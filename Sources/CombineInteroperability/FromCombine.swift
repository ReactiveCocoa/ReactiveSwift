#if canImport(Combine)
import Combine

extension Publisher {
	public func producer() -> SignalProducer<Output, Failure> {
		return SignalProducer { observer, lifetime in
			lifetime += self.sink(
				receiveCompletion: { completion in
					switch completion {
					case let .failure(error):
						observer.send(error: error)
					case .finished:
						observer.sendCompleted()
					}
				},
				receiveValue: observer.send(value:)
			)
		}
	}
}
#endif
