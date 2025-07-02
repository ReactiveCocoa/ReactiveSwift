extension Operators {
	internal final class SkipFirst<Value, Error: Swift.Error>: Observer, @unchecked Sendable {
		let downstream: any Observer<Value, Error>
		let count: Int
		var skipped: Int = 0

		init(downstream: some Observer<Value, Error>, count: Int) {
			precondition(count >= 1)

			self.downstream = downstream
			self.count = count
		}

		func receive(_ value: Value) {
			if skipped < count {
				skipped += 1
			} else {
				downstream.receive(value)
			}
		}

		func terminate(_ termination: Termination<Error>) {
			downstream.terminate(termination)
		}
	}
}
