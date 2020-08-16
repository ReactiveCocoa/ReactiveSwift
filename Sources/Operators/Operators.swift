

protocol Operator {
	associatedtype ProducedObserver: Observer
	associatedtype OutputValue
	associatedtype OutputError: Swift.Error

	func create<DownstreamObserver: Observer>(
		_ downstream: DownstreamObserver
	) -> ProducedObserver where DownstreamObserver.Value == OutputValue, DownstreamObserver.Error == OutputError
}

extension Never: Operator {
	typealias Upstream = Never
	typealias ProducedObserver = Never
	typealias OutputValue = Never
	typealias OutputError = Never

	var upstream: Never { fatalError() }
	func create<DownstreamObserver>(_ downstream: DownstreamObserver) -> Never where DownstreamObserver : Observer, Self.OutputError == DownstreamObserver.Error, Self.OutputValue == DownstreamObserver.Value {
		fatalError()
	}
}
