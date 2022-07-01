extension Operators {
	internal final class UniqueValues<Value, Identity: Hashable, Error: Swift.Error>: Observer, @unchecked Sendable {
		let downstream: any Observer<Value, Error>
		let extract: (Value) -> Identity

		var seenIdentities: Set<Identity> = []

		init(downstream: some Observer<Value, Error>, extract: @escaping (Value) -> Identity) {
			self.downstream = downstream
			self.extract = extract
		}

		func receive(_ value: Value) {
			let identity = extract(value)
			let (inserted, _) = seenIdentities.insert(identity)

			if inserted {
				downstream.receive(value)
			}
		}

		func terminate(_ termination: Termination<Error>) {
			downstream.terminate(termination)
		}
	}
}
