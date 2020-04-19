#if canImport(Combine)
import Combine

extension Lifetime {
	@available(macOS 10.15, iOS 13.0, tvOS 13.0, macCatalyst 13.0, watchOS 6.0, *)
	@discardableResult
	public static func += <C: Cancellable>(lhs: Lifetime, rhs: C) -> Disposable? {
		lhs.observeEnded(rhs.cancel)
	}
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, macCatalyst 13.0, watchOS 6.0, *)
extension AnyDisposable: Cancellable {
	public func cancel() {
		dispose()
	}
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, macCatalyst 13.0, watchOS 6.0, *)
extension SerialDisposable: Cancellable {
	public func cancel() {
		dispose()
	}
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, macCatalyst 13.0, watchOS 6.0, *)
extension CompositeDisposable: Cancellable {
	public func cancel() {
		dispose()
	}
}
#endif
