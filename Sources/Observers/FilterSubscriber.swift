internal final class FilterSubscriber<Value, Error: Swift.Error>: Subscriber<Value, Error> {
	let downstream: Subscriber<Value, Error>
	let predicate: (Value) -> Bool

	init(downstream: Subscriber<Value, Error>, predicate: @escaping (Value) -> Bool) {
		self.downstream = downstream
		self.predicate = predicate
	}

	override func receive(_ value: Value) {
		if predicate(value) {
			downstream.receive(value)
		}
	}

	override func terminate(_ termination: Termination<Error>) {
		downstream.terminate(termination)
	}
}
