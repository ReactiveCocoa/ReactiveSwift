#if canImport(Combine)
import Combine

extension Lifetime {
	@available(macOS 10.15, iOS 13.0, tvOS 13.0, macCatalyst 13.0, watchOS 6.0, *)
	@discardableResult
	public static func += <C: Cancellable>(lhs: Lifetime, rhs: C?) -> Disposable? {
		rhs.flatMap { lhs.observeEnded($0.cancel) }
	}
}
#endif

