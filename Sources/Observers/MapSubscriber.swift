internal final class MapSubscriber<InputValue, OutputValue, Error: Swift.Error>: Subscriber<InputValue, Error> {
	let downstream: Subscriber<OutputValue, Error>
	let transform: (InputValue) -> OutputValue

	init(downstream: Subscriber<OutputValue, Error>, transform: @escaping (InputValue) -> OutputValue) {
		self.downstream = downstream
		self.transform = transform
	}

	override func receive(_ value: InputValue) {
		downstream.receive(transform(value))
	}

	override func terminate(_ termination: Termination<Error>) {
		downstream.terminate(termination)
	}
}
