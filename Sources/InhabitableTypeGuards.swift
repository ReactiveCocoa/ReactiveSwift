import Result

// Observation
extension SignalProducer where Value == Never {
	@discardableResult
	@available(*, deprecated, message:"`Result.success` is never delivered - `Value` is inhabitable (Instantiation at runtime would trap)")
	public func startWithResult(_ action: @escaping (Result<Value, Error>) -> Void) -> Disposable { observingInhabitableTypeError() }

	@discardableResult
	@available(*, deprecated, message:"Observer is never called - `Value` is inhabitable (Instantiation at runtime would trap)")
	public func startWithValues(_ action: @escaping (Value) -> Void) -> Disposable { observingInhabitableTypeError() }
}

extension SignalProducer where Value == Never, Error == NoError {
	@discardableResult
	@available(*, deprecated, message:"Observer is never called - `Value` and `Error` are inhabitable (Instantiation at runtime would trap)")
	public func startWithResult(_ action: @escaping (Result<Value, Error>) -> Void) -> Disposable { observingInhabitableTypeError() }
}

extension SignalProducer where Error == NoError {
	@discardableResult
	@available(*, deprecated, message:"`Error` is inhabitable so the observer is never called (Instantiation at runtime would trap)")
	public func startWithFailed(_ action: @escaping (Error) -> Void) -> Disposable { observingInhabitableTypeError() }
}

extension Signal where Value == Never {
	@discardableResult
	@available(*, deprecated, message:"`Result.success` is never delivered - `Value` is inhabitable (Instantiation at runtime would trap)")
	public func observeResult(_ action: @escaping (Result<Value, Error>) -> Void) -> Disposable? { observingInhabitableTypeError() }

	@discardableResult
	@available(*, deprecated, message:"Observer is never called - `Value` is inhabitable (Instantiation at runtime would trap)")
	public func observeValues(_ action: @escaping (Value) -> Void) -> Disposable? { observingInhabitableTypeError() }
}

extension Signal where Value == Never, Error == NoError {
	@discardableResult
	@available(*, deprecated, message:"Observer is never called - `Value` and `Error` are inhabitable (Instantiation at runtime would trap)")
	public func observeResult(_ action: @escaping (Result<Value, Error>) -> Void) -> Disposable? { observingInhabitableTypeError() }
}

extension Signal where Error == NoError {
	@discardableResult
	@available(*, deprecated, message:"Observer is never invoked - `Error` is inhabitable (Instantiation at runtime would trap)")
	public func observeFailed(_ action: @escaping (Error) -> Void) -> Disposable? { observingInhabitableTypeError() }
}

// flatMap
extension SignalProducer where Value == Never {
	@discardableResult
	@available(*, deprecated, message:"Use `promoteValue` instead - `Value` is inhabitable (Instantiation at runtime would trap)")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Inner) -> SignalProducer<Inner.Value, Error> where Inner.Error == Error { observingInhabitableTypeError() }

	@discardableResult
	@available(*, deprecated, message:"Use `promoteValue` instead - `Value` is inhabitable (Instantiation at runtime would trap)")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Inner) -> SignalProducer<Inner.Value, Error> where Inner.Error == NoError { observingInhabitableTypeError() }
}

extension SignalProducer where Value == Never, Error == NoError {
	@discardableResult
	@available(*, deprecated, message:"Use `promoteValue` instead - `Value` and `Error` are inhabitable (Instantiation at runtime would trap)")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Inner) -> SignalProducer<Inner.Value, Inner.Error> { observingInhabitableTypeError() }

	@discardableResult
	@available(*, deprecated, message:"Use `promoteValue` instead - `Value` and `Error` are inhabitable (Instantiation at runtime would trap)")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Inner) -> SignalProducer<Inner.Value, Inner.Error> where Inner.Error == Error { observingInhabitableTypeError() }
}

extension SignalProducer where Error == NoError {
	@discardableResult
	@available(*, deprecated, message:"Use `promoteError` instead - `Error` is inhabitable (Instantiation at runtime would trap)")
	public func flatMapError<NewError>(_ transform: @escaping (Error) -> SignalProducer<Value, NewError>) -> SignalProducer<Value, NewError> { observingInhabitableTypeError() }
}

extension Signal where Value == Never {
	@discardableResult
	@available(*, deprecated, message:"Use `promoteValue` instead - `Value` is inhabitable (Instantiation at runtime would trap)")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Inner) -> Signal<Inner.Value, Error> where Inner.Error == Error { observingInhabitableTypeError() }

	@discardableResult
	@available(*, deprecated, message:"Use `promoteValue` instead - `Value` is inhabitable (Instantiation at runtime would trap)")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Inner) -> Signal<Inner.Value, Error> where Inner.Error == NoError { observingInhabitableTypeError() }

}

extension Signal where Value == Never, Error == NoError {
	@discardableResult
	@available(*, deprecated, message:"Use `promoteValue` instead - `Value` and `Error` are inhabitable (Instantiation at runtime would trap)")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Inner) -> Signal<Inner.Value, Inner.Error> { observingInhabitableTypeError() }

	@discardableResult
	@available(*, deprecated, message:"Use `promoteValue` instead - `Value` and `Error` are inhabitable (Instantiation at runtime would trap)")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Inner) -> Signal<Inner.Value, Inner.Error> where Inner.Error == Error { observingInhabitableTypeError() }
}

extension Signal where Error == NoError {
	@discardableResult
	@available(*, deprecated, message:"Use `promoteError` instead - `Error` is inhabitable (Instantiation at runtime would trap)")
	public func flatMapError<NewError>(_ transform: @escaping (Error) -> SignalProducer<Value, NewError>) -> Signal<Value, NewError> { observingInhabitableTypeError() }
}

@inline(never)
private func observingInhabitableTypeError() -> Never {
	fatalError("Detected an attempt to instantiate a `Signal` or `SignalProducer` that observes an inhabitable type, e.g. `Never` or `NoError`. This is considered a logical error, and appropriate operators should be used instead. Please refer to the warnings raised by the compiler.")
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
