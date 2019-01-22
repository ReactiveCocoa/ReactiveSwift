extension Result: SignalProducerConvertible {
	public var producer: SignalProducer<Success, Failure> {
		return .init(result: self)
	}
	
	public var value: Success? {
		switch self {
		case let .success(value): return value
		case .failure: return nil
		}
	}
	
	public var error: Failure? {
		switch self {
		case .success: return nil
		case let .failure(error): return error
		}
	}
}

/// A protocol that can be used to constrain associated types as `Result`.
public protocol ResultProtocol {
	associatedtype Success
	associatedtype Failure: Swift.Error
	
	init(success: Success)
	init(failure: Failure)
	
	var result: Result<Success, Failure> { get }
}

extension Result: ResultProtocol {
	public init(success: Success) {
		self = .success(success)
	}
	
	public init(failure: Failure) {
		self = .failure(failure)
	}
	
	public var result: Result<Success, Failure> {
		return self
	}
}
