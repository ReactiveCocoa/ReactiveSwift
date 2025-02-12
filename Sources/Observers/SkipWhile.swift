extension Operators {
	internal final class SkipWhile<Value, Error: Swift.Error>: Observer, @unchecked Sendable {
		let downstream: any Observer<Value, Error>
		let shouldContinueToSkip: (Value) -> Bool
		var isSkipping = true

		init(downstream: some Observer<Value, Error>, shouldContinueToSkip: @escaping (Value) -> Bool) {
			self.downstream = downstream
			self.shouldContinueToSkip = shouldContinueToSkip
		}

		func receive(_ value: Value) {
			isSkipping = isSkipping && shouldContinueToSkip(value)

			if !isSkipping {
				downstream.receive(value)
			}
		}

		func terminate(_ termination: Termination<Error>) {
			downstream.terminate(termination)
		}
	}
}
