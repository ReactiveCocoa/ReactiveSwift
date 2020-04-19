#if canImport(Combine)
import Combine

extension Lifetime {
	@discardableResult
	public static func += <C: Cancellable>(lhs: Lifetime, rhs: C) -> Disposable? {
		lhs.observeEnded(rhs.cancel)
	}
}

extension AnyDisposable: Cancellable {
	public func cancel() {
		dispose()
	}
}

extension SerialDisposable: Cancellable {
	public func cancel() {
		dispose()
	}
}

extension CompositeDisposable: Cancellable {
	public func cancel() {
		dispose()
	}
}
#endif
