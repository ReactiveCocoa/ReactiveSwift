extension Operators {
	internal final class TakeLast<Value, Error: Swift.Error>: Observer, @unchecked Sendable {
		let downstream: any Observer<Value, Error>
		let count: Int
		var buffer: [Value] = []

		init(downstream: some Observer<Value, Error>, count: Int) {
			precondition(count >= 1)

			self.downstream = downstream
			self.count = count

			buffer.reserveCapacity(count)
		}

		func receive(_ value: Value) {
			// To avoid exceeding the reserved capacity of the buffer,
			// we remove then add. Remove elements until we have room to
			// add one more.
			while (buffer.count + 1) > count {
				buffer.remove(at: 0)
			}

			buffer.append(value)
		}

		func terminate(_ termination: Termination<Error>) {
			if case .completed = termination {
				buffer.forEach(downstream.receive)
				buffer = []
			}

			downstream.terminate(termination)
		}
	}
}
