extension Operators {
	internal final class Materialize<Value, Error: Swift.Error>: Observer {
		let downstream: any Observer<Signal<Value, Error>.Event, Never>

		init(downstream: some Observer<Signal<Value, Error>.Event, Never>) {
			self.downstream = downstream
		}

		func receive(_ value: Value) {
			downstream.receive(.value(value))
		}

		func terminate(_ termination: Termination<Error>) {
			downstream.receive(Signal<Value, Error>.Event(termination))

			switch termination {
			case .completed, .failed:
				downstream.terminate(.completed)
			case .interrupted:
				downstream.terminate(.interrupted)
			}
		}
	}
}
