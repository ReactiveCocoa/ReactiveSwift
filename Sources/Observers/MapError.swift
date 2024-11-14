extension Operators {
	internal final class MapError<Value, InputError: Swift.Error, OutputError: Swift.Error>: Observer {
		let downstream: any Observer<Value, OutputError>
		let transform: @Sendable (InputError) -> OutputError

		init(downstream: some Observer<Value, OutputError>, transform: @escaping @Sendable (InputError) -> OutputError) {
			self.downstream = downstream
			self.transform = transform
		}

		func receive(_ value: Value) {
			downstream.receive(value)
		}

		func terminate(_ termination: Termination<InputError>) {
			switch termination {
			case .completed:
				downstream.terminate(.completed)
			case let .failed(error):
				downstream.terminate(.failed(transform(error)))
			case .interrupted:
				downstream.terminate(.interrupted)
			}
		}
	}
}
