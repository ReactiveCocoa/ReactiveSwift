
public protocol Observer {
	associatedtype Value
	associatedtype Error: Swift.Error

	func send(value: Value)
	func send(error: Error)
	func sendCompleted()
	func sendInterrupted()
}

public protocol ValueTransformingObserver: Observer where Downstream.Error == Error {
	associatedtype Downstream: Observer

	var downstream: Downstream { get }
}

extension ValueTransformingObserver {
	public func send(error: Error) { downstream.send(error: error) }
	public func sendCompleted() { downstream.sendCompleted() }
	public func sendInterrupted() { downstream.sendInterrupted() }
}

extension Signal.Observer: Observer {}

extension Never: Observer {
	public func send(value: Never) {}
	public func send(error: Never) {}
	public func sendCompleted() {}
	public func sendInterrupted() {}

	public typealias Value = Never
	public typealias Error = Never
}
