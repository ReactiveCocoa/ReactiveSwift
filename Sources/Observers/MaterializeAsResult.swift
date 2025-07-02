extension Operators {
	internal final class MaterializeAsResult<Value, Error: Swift.Error>: Observer {
		let downstream: any Observer<Result<Value, Error>, Never>

		init(downstream: some Observer<Result<Value, Error>, Never>) {
			self.downstream = downstream
		}

		func receive(_ value: Value) {
			downstream.receive(.success(value))
		}

		func terminate(_ termination: Termination<Error>) {
			switch termination {
			case .completed:
				downstream.terminate(.completed)
			case let .failed(error):
				downstream.receive(.failure(error))
				downstream.terminate(.completed)
			case .interrupted:
				downstream.terminate(.interrupted)
			}
		}
	}
}
