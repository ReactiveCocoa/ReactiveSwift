import Foundation
import Dispatch
import Result

// MARK: Unavailable methods in ReactiveSwift 3.0.
extension Signal {
	@available(*, unavailable, message:"Use the `Signal.init` that accepts a two-argument generator.")
	public convenience init(_ generator: (Observer) -> Disposable?) { fatalError() }
}

// MARK: Deprecated types in ReactiveSwift 2.x.
