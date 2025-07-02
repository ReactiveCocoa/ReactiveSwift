extension Operators {
	internal final class SkipRepeats<Value, Error: Swift.Error>: Observer, @unchecked Sendable {
		let downstream: any Observer<Value, Error>
		let isEquivalent: (Value, Value) -> Bool

		var previous: Value? = nil

		init(downstream: some Observer<Value, Error>, isEquivalent: @escaping (Value, Value) -> Bool) {
			self.downstream = downstream
			self.isEquivalent = isEquivalent
		}

		func receive(_ value: Value) {
			let isRepeating = previous.map { isEquivalent($0, value) } ?? false
			previous = value

			if !isRepeating {
				downstream.receive(value)
			}
		}

		func terminate(_ termination: Termination<Error>) {
			downstream.terminate(termination)
		}
	}
}
