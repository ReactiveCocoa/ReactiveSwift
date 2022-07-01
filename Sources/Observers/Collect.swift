extension Operators {
	internal final class Collect<Value, Error: Swift.Error>: Observer, @unchecked Sendable {
		let downstream: any Observer<[Value], Error>
		let modify: @Sendable (_ collected: inout [Value], _ latest: Value) -> [Value]?

		private var values: [Value] = []
		private var hasReceivedValues = false

		convenience init(downstream: some Observer<[Value], Error>, shouldEmit: @escaping (_ collected: [Value], _ latest: Value) -> Bool) {
			self.init(downstream: downstream, modify: { collected, latest in
				if shouldEmit(collected, latest) {
					defer { collected = [latest] }
					return collected
				}

				collected.append(latest)
				return nil
			})
		}

		convenience init(downstream: some Observer<[Value], Error>, shouldEmit: @escaping (_ collected: [Value]) -> Bool) {
			self.init(downstream: downstream, modify: { collected, latest in
				collected.append(latest)

				if shouldEmit(collected) {
					defer { collected.removeAll(keepingCapacity: true) }
					return collected
				}

				return nil
			})
		}

		private init(downstream: some Observer<[Value], Error>, modify: @escaping @Sendable (_ collected: inout [Value], _ latest: Value) -> [Value]?) {
			self.downstream = downstream
			self.modify = modify
		}

		func receive(_ value: Value) {
			if let outgoing = modify(&values, value) {
				downstream.receive(outgoing)
			}

			if !hasReceivedValues {
				hasReceivedValues = true
			}
		}

		func terminate(_ termination: Termination<Error>) {
			if case .completed = termination {
				if !values.isEmpty {
					downstream.receive(values)
					values.removeAll()
				} else if !hasReceivedValues {
					downstream.receive([])
				}
			}

			downstream.terminate(termination)
		}
	}
}
