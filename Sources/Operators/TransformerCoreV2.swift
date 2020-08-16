
struct TransformerCoreV2<AppliedOperator: Operator> {
	let op: AppliedOperator
	let sideEffect: (AppliedOperator.ProducedObserver) -> Void

	init<SourceValue, SourceError>(_ valueType: SourceValue.Type, _ errorType: SourceError.Type, _ sideEffect: @escaping (Source<SourceValue, SourceError>.SourceObserver) -> Void) where AppliedOperator == Source<SourceValue, SourceError> {
		self.op = Source()
		self.sideEffect = sideEffect
	}

	init(op: AppliedOperator, sideEffect: @escaping (AppliedOperator.ProducedObserver) -> Void) {
		self.op = op
		self.sideEffect = sideEffect
	}

	func chain<NewOperator: Operator>(
		_ transform: (AppliedOperator) -> NewOperator
	) -> TransformerCoreV2<NewOperator> where AppliedOperator.ProducedObserver == NewOperator.ProducedObserver {
		TransformerCoreV2<NewOperator>(
			op: transform(self.op),
			sideEffect: sideEffect
		)
	}

	func start(_ observer: Signal<AppliedOperator.OutputValue, AppliedOperator.OutputError>.Observer) {
		let source = op.create(observer)
		sideEffect(source)
	}
}

func test() -> Any {
	let source = TransformerCoreV2(Int8.self, Never.self) { observer in
		observer.send(value: 1)
	}

	let product = source
		.chain { MapOperator(upstream: $0, transform: Int16.init) }
		.chain { MapOperator(upstream: $0, transform: Int32.init) }
		.chain { MapOperator(upstream: $0, transform: Int64.init) }

	return product
}
