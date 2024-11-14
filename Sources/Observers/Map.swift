extension Operators {
	internal final class Map<InputValue, OutputValue, Error: Swift.Error>: Observer {
		let downstream: any Observer<OutputValue, Error>
		let transform: @Sendable (InputValue) -> OutputValue

		init(downstream: some Observer<OutputValue, Error>, transform: @escaping @Sendable (InputValue) -> OutputValue) {
			self.downstream = downstream
			self.transform = transform
		}

		func receive(_ value: InputValue) {
			downstream.receive(transform(value))
		}

		func terminate(_ termination: Termination<Error>) {
			downstream.terminate(termination)
		}
	}
}
