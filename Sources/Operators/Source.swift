struct Source<OutputValue, OutputError: Swift.Error>: Operator {
	var upstream: Never { fatalError() }

	func create<DownstreamObserver>(
		_ downstream: DownstreamObserver
	) -> SourceObserver where DownstreamObserver: Observer, OutputError == DownstreamObserver.Error, OutputValue == DownstreamObserver.Value {
		fatalError()
	}

	struct SourceObserver: ReactiveSwift.Observer {
		// type erasure
		// let downstream: Downstream

		func send(value: OutputValue) {
		}

		func send(error: OutputError) {
		}

		func sendCompleted() {
		}

		func sendInterrupted() {
		}
	}
}
