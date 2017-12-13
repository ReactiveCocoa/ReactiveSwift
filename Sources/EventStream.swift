internal protocol EventStream {
	associatedtype Value
	associatedtype Error: Swift.Error

	@discardableResult
	func subscribe(_ setup: (Disposable) -> Signal<Value, Error>.Observer) -> Disposable
}

extension Signal: EventStream {
	internal func subscribe(_ setup: (Disposable) -> Signal<Value, Error>.Observer) -> Disposable {
		let d = _SimpleDisposable()
		let observer = setup(d)

		guard !d.isDisposed, let detacher = observe(observer) else {
			return NopDisposable.shared
		}

		return detacher
	}
}

extension SignalProducer: EventStream {
	internal func subscribe(_ setup: (Disposable) -> Signal<Value, Error>.Observer) -> Disposable {
		return startWithInterrupter(setup)
	}
}
