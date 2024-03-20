extension Operators {
	internal final class DematerializeResults<Result>: Observer where Result: ResultProtocol {
		let downstream: any Observer<Result.Success, Result.Failure>

		init(downstream: some Observer<Result.Success, Result.Failure>) {
			self.downstream = downstream
		}

		func receive(_ value: Result) {
			switch value.result {
			case let .success(value):
				downstream.receive(value)
			case let .failure(error):
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
