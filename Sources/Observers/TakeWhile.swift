extension Operators {
	internal final class TakeWhile<Value, Error: Swift.Error>: Observer, @unchecked Sendable {
		let downstream: any Observer<Value, Error>
		let shouldContinue: @Sendable (Value) -> Bool

		init(downstream: some Observer<Value, Error>, shouldContinue: @Sendable @escaping (Value) -> Bool) {
			self.downstream = downstream
			self.shouldContinue = shouldContinue
		}

		func receive(_ value: Value) {
			if !shouldContinue(value) {
				downstream.terminate(.completed)
			} else {
				downstream.receive(value)
			}
		}

		func terminate(_ termination: Termination<Error>) {
			downstream.terminate(termination)
		}
	}
}
