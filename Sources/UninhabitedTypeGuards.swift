import Result

// Observation

extension SignalProducer {
	@available(*, unavailable, message:"Transform the error to `NoError` beforehand, or use `startWithResult` instead")
	@discardableResult
	public func startWithValues(_ action: @escaping (Value) -> Void) -> Disposable { observingUninhabitedTypeError() }
}

extension Signal {
	@available(*, unavailable, message:"Transform the error to `NoError` beforehand, or use `observeResult` instead")
	@discardableResult
	public func observeValues(_ action: @escaping (Value) -> Void) -> Disposable? { observingUninhabitedTypeError() }
}

extension SignalProducer where Value == Never {
	@discardableResult
	@available(*, deprecated, message:"`Result.success` is never delivered - value type `Never` is uninstantiable (Use at runtime would trap)")
	public func startWithResult(_ action: @escaping (Result<Value, Error>) -> Void) -> Disposable { observingUninhabitedTypeError() }
}

extension SignalProducer where Value == Never, Error == NoError {
	@discardableResult
	@available(*, deprecated, message:"Observer is never called - value type `Never` and error type `NoError` are uninstantiable (Use at runtime would trap)")
	public func startWithResult(_ action: @escaping (Result<Value, Error>) -> Void) -> Disposable { observingUninhabitedTypeError() }

	@discardableResult
	@available(*, deprecated, message:"Observer is never called - value type `Never` is uninstantiable (Use at runtime would trap)")
	public func startWithValues(_ action: @escaping (Value) -> Void) -> Disposable { observingUninhabitedTypeError() }
}

extension SignalProducer where Error == NoError {
	@discardableResult
	@available(*, deprecated, message:"Observer is never called - error type `NoError` is uninstantiable (Use at runtime would trap)")
	public func startWithFailed(_ action: @escaping (Error) -> Void) -> Disposable { observingUninhabitedTypeError() }
}

extension Signal where Value == Never {
	@discardableResult
	@available(*, deprecated, message:"`Result.success` is never delivered - value type `Never` is uninstantiable (Use at runtime would trap)")
	public func observeResult(_ action: @escaping (Result<Value, Error>) -> Void) -> Disposable? { observingUninhabitedTypeError() }
}

extension Signal where Value == Never, Error == NoError {
	@discardableResult
	@available(*, deprecated, message:"Observer is never called - value type `Never` and error type `NoError` are uninstantiable (Use at runtime would trap)")
	public func observeResult(_ action: @escaping (Result<Value, Error>) -> Void) -> Disposable? { observingUninhabitedTypeError() }

	@discardableResult
	@available(*, deprecated, message:"Observer is never called - value type `Never` is uninstantiable (Use at runtime would trap)")
	public func observeValues(_ action: @escaping (Value) -> Void) -> Disposable? { observingUninhabitedTypeError() }
}

extension Signal where Error == NoError {
	@discardableResult
	@available(*, deprecated, message:"Observer is never invoked - error type `NoError` is uninstantiable (Use at runtime would trap)")
	public func observeFailed(_ action: @escaping (Error) -> Void) -> Disposable? { observingUninhabitedTypeError() }
}

// flatMap
extension SignalProducer where Value == Never {
	@discardableResult
	@available(*, deprecated, message:"Use `promoteValue` instead - value type `Never` is uninstantiable (Use at runtime would trap)")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Inner) -> SignalProducer<Inner.Value, Error> where Inner.Error == Error { observingUninhabitedTypeError() }

	@discardableResult
	@available(*, deprecated, message:"Use `promoteValue` instead - value type `Never` is uninstantiable (Use at runtime would trap)")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Inner) -> SignalProducer<Inner.Value, Error> where Inner.Error == NoError { observingUninhabitedTypeError() }
}

extension SignalProducer where Value == Never, Error == NoError {
	@discardableResult
	@available(*, deprecated, message:"Use `promoteValue` instead - value type `Never` and error type `NoError` are uninstantiable (Use at runtime would trap)")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Inner) -> SignalProducer<Inner.Value, Inner.Error> { observingUninhabitedTypeError() }

	@discardableResult
	@available(*, deprecated, message:"Use `promoteValue` instead - value type `Never` and error type `NoError` are uninstantiable (Use at runtime would trap)")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Inner) -> SignalProducer<Inner.Value, Inner.Error> where Inner.Error == Error { observingUninhabitedTypeError() }
}

extension SignalProducer where Error == NoError {
	@discardableResult
	@available(*, deprecated, message:"Use `promoteError` instead - error type `NoError` is uninstantiable (Use at runtime would trap)")
	public func flatMapError<NewError>(_ transform: @escaping (Error) -> SignalProducer<Value, NewError>) -> SignalProducer<Value, NewError> { observingUninhabitedTypeError() }
}

extension Signal where Value == Never {
	@discardableResult
	@available(*, deprecated, message:"Use `promoteValue` instead - value type `Never` is uninstantiable (Use at runtime would trap)")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Inner) -> Signal<Inner.Value, Error> where Inner.Error == Error { observingUninhabitedTypeError() }

	@discardableResult
	@available(*, deprecated, message:"Use `promoteValue` instead - value type `Never` is uninstantiable (Use at runtime would trap)")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Inner) -> Signal<Inner.Value, Error> where Inner.Error == NoError { observingUninhabitedTypeError() }

}

extension Signal where Value == Never, Error == NoError {
	@discardableResult
	@available(*, deprecated, message:"Use `promoteValue` instead - value type `Never` and error type `NoError` are uninstantiable (Use at runtime would trap)")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Inner) -> Signal<Inner.Value, Inner.Error> { observingUninhabitedTypeError() }

	@discardableResult
	@available(*, deprecated, message:"Use `promoteValue` instead - value type `Never` and error type `NoError` are uninstantiable (Use at runtime would trap)")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, _ transform: @escaping (Value) -> Inner) -> Signal<Inner.Value, Inner.Error> where Inner.Error == Error { observingUninhabitedTypeError() }
}

extension Signal where Error == NoError {
	@discardableResult
	@available(*, deprecated, message:"Use `promoteError` instead - error type `NoError` is uninstantiable (Use at runtime would trap)")
	public func flatMapError<NewError>(_ transform: @escaping (Error) -> SignalProducer<Value, NewError>) -> Signal<Value, NewError> { observingUninhabitedTypeError() }
}

@inline(never)
private func observingUninhabitedTypeError() -> Never {
	fatalError("Detected an attempt to observe (or create streams to transform) uninstantiable events. This is considered a logical error, and appropriate operators should be used instead. Please refer to the warnings raised by the compiler.")
}

/*
func test() {
	SignalProducer<Any, AnyError>.never.startWithValues { _ in }
	Signal<Any, AnyError>.never.observeValues { _ in }

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
