extension Operators {
	internal final class TakeUntil<Value, Error: Swift.Error>: Observer {
		let downstream: any Observer<Value, Error>
		let shouldContinue: @Sendable (Value) -> Bool

		init(downstream: some Observer<Value, Error>, shouldContinue: @escaping @Sendable (Value) -> Bool) {
			self.downstream = downstream
			self.shouldContinue = shouldContinue
		}

		func receive(_ value: Value) {
			downstream.receive(value)
			
			if !shouldContinue(value) {
				downstream.terminate(.completed)
			}
		}

		func terminate(_ termination: Termination<Error>) {
			downstream.terminate(termination)
		}
	}
}
