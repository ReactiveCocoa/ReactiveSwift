extension Operators {
	internal final class AttemptMap<InputValue, OutputValue, Error: Swift.Error>: Observer {
		let downstream: any Observer<OutputValue, Error>
		let transform: @Sendable (InputValue) -> Result<OutputValue, Error>

		init(downstream: some Observer<OutputValue, Error>, transform: @escaping @Sendable (InputValue) -> Result<OutputValue, Error>) {
			self.downstream = downstream
			self.transform = transform
		}

		func receive(_ value: InputValue) {
			switch transform(value) {
			case let .success(value):
				downstream.receive(value)
			case let .failure(error):
				downstream.terminate(.failed(error))
			}
		}

		func terminate(_ termination: Termination<Error>) {
			downstream.terminate(termination)
		}
	}
}
