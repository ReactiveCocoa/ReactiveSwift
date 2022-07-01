extension Operators {
	internal final class Dematerialize<Event>: Observer where Event: EventProtocol {
		let downstream: any Observer<Event.Value, Event.Error>

		init(downstream: some Observer<Event.Value, Event.Error>) {
			self.downstream = downstream
		}

		func receive(_ event: Event) {
			switch event.event {
			case let .value(value):
				downstream.receive(value)
			case .completed:
				downstream.terminate(.completed)
			case .interrupted:
				downstream.terminate(.interrupted)
			case let .failed(error):
				downstream.terminate(.failed(error))
			}
		}

		func terminate(_ termination: Termination<Never>) {
			switch termination {
			case .completed:
				downstream.terminate(.completed)
			case .interrupted:
				downstream.terminate(.interrupted)
			}
		}
	}
}
