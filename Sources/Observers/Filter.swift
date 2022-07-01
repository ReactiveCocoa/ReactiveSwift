extension Operators {
	internal final class Filter<Value, Error: Swift.Error>: Observer {
		let downstream: any Observer<Value, Error>
		let predicate: @Sendable (Value) -> Bool
		
		init(downstream: some Observer<Value, Error>, predicate: @escaping @Sendable (Value) -> Bool) {
			self.downstream = downstream
			self.predicate = predicate
		}
		
		func receive(_ value: Value) {
			if predicate(value) {
				downstream.receive(value)
			}
		}
		
		func terminate(_ termination: Termination<Error>) {
			downstream.terminate(termination)
		}
	}
}
