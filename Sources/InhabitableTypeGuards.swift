import Result

// Observation
extension SignalProducer where Value == Never {
	@discardableResult
	@available(*, deprecated, message:"`success` event is never delivered.")
	public func startWithResult(_ action: @escaping (Result<Value, Error>) -> Void) -> Disposable { fatalError() }

	@discardableResult
	@available(*, deprecated, message:"The observer is never invoked.")
	public func startWithValues(_ action: @escaping (Value) -> Void) -> Disposable { fatalError() }
}

extension SignalProducer where Value == Never, Error == NoError {
	@discardableResult
	@available(*, deprecated, message:"The observer is never invoked.")
	public func startWithResult(_ action: @escaping (Result<Value, Error>) -> Void) -> Disposable { fatalError() }
}

extension SignalProducer where Error == NoError {
	@discardableResult
	@available(*, deprecated, message:"The observer is never invoked.")
	public func startWithFailed(_ action: @escaping (Error) -> Void) -> Disposable { fatalError() }
}

extension Signal where Value == Never {
	@discardableResult
	@available(*, deprecated, message:"`success` event is never delivered.")
	public func observeResult(_ action: @escaping (Result<Value, Error>) -> Void) -> Disposable { fatalError() }

	@discardableResult
	@available(*, deprecated, message:"The observer is never invoked.")
	public func observeValues(_ action: @escaping (Value) -> Void) -> Disposable { fatalError() }
}

extension Signal where Value == Never, Error == NoError {
	@discardableResult
	@available(*, deprecated, message:"The observer is never invoked.")
	public func observeResult(_ action: @escaping (Result<Value, Error>) -> Void) -> Disposable { fatalError() }
}

extension Signal where Error == NoError {
	@discardableResult
	@available(*, deprecated, message:"The observer is never invoked.")
	public func observeFailed(_ action: @escaping (Error) -> Void) -> Disposable { fatalError() }
}

// flatMap
extension SignalProducer where Value == Never {
	@discardableResult
	@available(*, deprecated, message:"Use `promoteValue` instead.")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Inner) -> SignalProducer<Inner.Value, Error> where Inner.Error == Error { fatalError() }

	@discardableResult
	@available(*, deprecated, message:"Use `promoteValue` instead.")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Inner) -> SignalProducer<Inner.Value, Error> where Inner.Error == NoError { fatalError() }
}

extension SignalProducer where Value == Never, Error == NoError {
	@discardableResult
	@available(*, deprecated, message:"Use `promoteValue` instead.")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Inner) -> SignalProducer<Inner.Value, Inner.Error> { fatalError() }

	@discardableResult
	@available(*, deprecated, message:"Use `promoteValue` instead.")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Inner) -> SignalProducer<Inner.Value, Inner.Error> where Inner.Error == Error { fatalError() }
}

extension SignalProducer where Error == NoError {
	@discardableResult
	@available(*, deprecated, message:"Use `promoteError` instead.")
	public func flatMapError<NewError>(_ transform: @escaping (Error) -> SignalProducer<Value, NewError>) -> SignalProducer<Value, NewError> { fatalError() }
}

extension Signal where Value == Never {
	@discardableResult
	@available(*, deprecated, message:"Use `promoteValue` instead.")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Inner) -> Signal<Inner.Value, Error> where Inner.Error == Error { fatalError() }

	@discardableResult
	@available(*, deprecated, message:"Use `promoteValue` instead.")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Inner) -> Signal<Inner.Value, Error> where Inner.Error == NoError { fatalError() }

}

extension Signal where Value == Never, Error == NoError {
	@discardableResult
	@available(*, deprecated, message:"Use `promoteValue` instead.")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Inner) -> Signal<Inner.Value, Inner.Error> { fatalError() }

	@discardableResult
	@available(*, deprecated, message:"Use `promoteValue` instead.")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Inner) -> Signal<Inner.Value, Inner.Error> where Inner.Error == Error { fatalError() }
}

extension Signal where Error == NoError {
	@discardableResult
	@available(*, deprecated, message:"Use `promoteError` instead.")
	public func flatMapError<NewError>(_ transform: @escaping (Error) -> SignalProducer<Value, NewError>) -> Signal<Value, NewError> { fatalError() }
}

/*
func test() {
	SignalProducer<Never, AnyError>.never.startWithResult { _ in }
	SignalProducer<Never, NoError>.never.startWithResult { _ in }
	SignalProducer<Any, NoError>.never.startWithFailed { _ in }
	SignalProducer<Never, NoError>.never.startWithFailed { _ in }
	Signal<Never, AnyError>.never.observeResult { _ in }
	Signal<Never, NoError>.never.observeResult { _ in }
	Signal<Any, NoError>.never.observeFailed { _ in }
	Signal<Never, NoError>.never.observeFailed { _ in }

	SignalProducer<Never, AnyError>.never.flatMap(.latest) { _ in SignalProducer<Int, AnyError>.empty }
	SignalProducer<Never, AnyError>.never.flatMap(.latest) { _ in SignalProducer<Int, NoError>.empty }
	SignalProducer<Never, NoError>.never.flatMap(.latest) { _ in SignalProducer<Int, AnyError>.empty }
	SignalProducer<Never, NoError>.never.flatMap(.latest) { _ in SignalProducer<Int, NoError>.empty }
	SignalProducer<Never, NoError>.never.flatMapError { _ in SignalProducer<Never, AnyError>.empty }
	SignalProducer<Never, NoError>.never.flatMapError { _ in SignalProducer<Never, NoError>.empty }

	Signal<Never, AnyError>.never.flatMap(.latest) { _ in SignalProducer<Int, AnyError>.empty }
	Signal<Never, AnyError>.never.flatMap(.latest) { _ in SignalProducer<Int, NoError>.empty }
	Signal<Never, NoError>.never.flatMap(.latest) { _ in SignalProducer<Int, AnyError>.empty }
	Signal<Never, NoError>.never.flatMap(.latest) { _ in SignalProducer<Int, NoError>.empty }
	Signal<Never, NoError>.never.flatMapError { _ in SignalProducer<Never, AnyError>.empty }
	Signal<Never, NoError>.never.flatMapError { _ in SignalProducer<Never, NoError>.empty }
}
*/
