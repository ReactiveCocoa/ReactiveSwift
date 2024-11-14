extension Operators {
	internal final class ScanMap<Value, State, Result, Error: Swift.Error>: Observer, @unchecked Sendable {
		let downstream: any Observer<Result, Error>
		let next: @Sendable (inout State, Value) -> Result
		var accumulator: State

		init(downstream: some Observer<Result, Error>, initial: State, next: @escaping @Sendable (inout State, Value) -> Result) {
			self.downstream = downstream
			self.accumulator = initial
			self.next = next
		}

		func receive(_ value: Value) {
			let result = next(&accumulator, value)
			downstream.receive(result)
		}

		func terminate(_ termination: Termination<Error>) {
			downstream.terminate(termination)
		}
	}
}
