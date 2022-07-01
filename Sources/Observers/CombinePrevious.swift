extension Operators {
	internal final class CombinePrevious<Value, Error: Swift.Error>: Observer, @unchecked Sendable {
		let downstream: any Observer<(Value, Value), Error>
		var previous: Value?

		init(downstream: some Observer<(Value, Value), Error>, initial: Value?) {
			self.downstream = downstream
			self.previous = initial
		}

		func receive(_ value: Value) {
			if let previous = previous {
				downstream.receive((previous, value))
			}

			previous = value
		}

		func terminate(_ termination: Termination<Error>) {
			downstream.terminate(termination)
		}
	}
}
