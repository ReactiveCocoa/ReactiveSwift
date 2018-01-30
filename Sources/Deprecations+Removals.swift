import Foundation
import Dispatch
import Result

// MARK: Unavailable methods in ReactiveSwift 3.0.
extension Signal {
	@available(*, unavailable, message:"Use the `Signal.init` that accepts a two-argument generator.")
	public convenience init(_ generator: (Observer) -> Disposable?) { fatalError() }
}

extension Lifetime {
	@discardableResult
	@available(*, unavailable, message:"Use `observeEnded(_:)` with a method reference to `dispose()` instead.")
	public func add(_ d: Disposable?) -> Disposable? { fatalError() }
}

// MARK: Deprecated types

extension Signal {
	@available(*, deprecated, renamed: "compactMap(_:)")
	public func filterMap<U>(_ transform: @escaping (Value) -> U?) -> Signal<U, Error> {
		return compactMap(transform)
	}
}

extension Signal where Value: OptionalProtocol {
	@available(*, deprecated, renamed: "compact()")
	public func skipNil() -> Signal<Value.Wrapped, Error> {
		return compact()
	}
}

extension SignalProducer {
	@available(*, deprecated, renamed: "compactMap(_:)")
	public func filterMap<U>(_ transform: @escaping (Value) -> U?) -> SignalProducer<U, Error> {
		return compactMap(transform)
	}
}

extension SignalProducer where Value: OptionalProtocol {
	@available(*, deprecated, renamed: "compact()")
	public func skipNil() -> SignalProducer<Value.Wrapped, Error> {
		return compact()
	}
}
