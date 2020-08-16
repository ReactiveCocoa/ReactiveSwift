struct MapOperator<Upstream: Operator, NewValue>: Operator {
	typealias OutputValue = NewValue
	typealias OutputError = Upstream.OutputError

	let upstream: Upstream
	let transform: (Upstream.OutputValue) -> NewValue

	func create<DownstreamObserver: Observer>(
		_ downstream: DownstreamObserver
	) -> Upstream.ProducedObserver where DownstreamObserver.Value == OutputValue, DownstreamObserver.Error == OutputError {
		upstream.create(
			MapObserver<Upstream.OutputValue, DownstreamObserver>(
				downstream: downstream,
				transform: transform
			)
		)
	}
}

struct MapObserver<Value, Downstream: Observer>: ValueTransformingObserver {
	typealias Error = Downstream.Error

	let downstream: Downstream
	let transform: (Value) -> Downstream.Value

	init(downstream: Downstream, transform: @escaping (Value) -> Downstream.Value) {
		self.downstream = downstream
		self.transform = transform
	}

	func send(value: Value) {
		downstream.send(value: transform(value))
	}
}
