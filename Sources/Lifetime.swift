import Foundation
import enum Result.NoError

/// Represents the lifetime of an object, and provides a hook to observe when
/// the object deinitializes.
public final class Lifetime {
	/// MARK: Type properties and methods

	/// A `Lifetime` that has already ended.
	public static var empty: Lifetime {
		return Lifetime(ended: .empty)
	}

	/// MARK: Instance properties

	/// A signal that sends a `completed` event when the lifetime ends.
	public let ended: Signal<(), NoError>

	/// MARK: Initializers

	/// Initialize a `Lifetime` object with the supplied ended signal.
	///
	/// - parameters:
	///   - signal: The ended signal.
	private init(ended signal: Signal<(), NoError>) {
		ended = signal
	}

	/// Initialize a `Lifetime` from a lifetime token, which is expected to be
	/// associated with an object.
	///
	/// - important: The resulting lifetime object does not retain the lifetime
	///              token.
	///
	/// - parameters:
	///   - token: A lifetime token for detecting the deinitialization of the
	///            associated object.
	public convenience init(_ token: Token) {
		self.init(ended: token.ended)
	}

	/// Create a lifetime that is an OR of `self` and `other`.
	///
	/// - parameters:
	///   - other: The lifetime to be composed with.
	///
	/// - returns:
	///   An OR lifetime.
	public func or(_ other: Lifetime) -> Lifetime {
		return Lifetime(ended: ended.zip(with: other.ended).map { _ in })
	}

	/// Create a lifetime that is an AND of `self` and `other`.
	///
	/// - parameters:
	///   - other: The lifetime to be composed with.
	///
	/// - returns:
	///   An AND lifetime.
	public func and(_ other: Lifetime) -> Lifetime {
		return Lifetime(ended: ended.combineLatest(with: other.ended).map { _ in })
	}

	/// Attach a disposable to `lifetime`.
	///
	/// - parameters:
	///   - lifetime: The lifetime being attached.
	///   - disposable: The disposable to be attached.
	///
	/// - returns:
	///   A cancel disposable to detach the disposable, or `nil` if the lifetime
	///   has terminated.
	@discardableResult
	public static func += (lifetime: Lifetime, disposable: Disposable?) -> Disposable? {
		return disposable.flatMap { disposable in
			return lifetime.ended.observeCompleted(disposable.dispose)
		}
	}

	/// Attach an action to `lifetime`.
	///
	/// - parameters:
	///   - lifetime: The lifetime being attached.
	///   - action: The action to be attached.
	///
	/// - returns:
	///   A cancel disposable to detach the action, or `nil` if the lifetime has
	///   terminated.
	@discardableResult
	public static func += (lifetime: Lifetime, action: @escaping () -> Void) -> Disposable? {
		return lifetime.ended.observeCompleted(action)
	}

	/// A token object which completes its signal when it deinitializes.
	///
	/// It is generally used in conjuncion with `Lifetime` as a private
	/// deinitialization trigger.
	///
	/// ```
	/// class MyController {
	///		private let token = Lifetime.Token()
	///		public var lifetime: Lifetime {
	///			return Lifetime(token)
	///		}
	/// }
	/// ```
	public final class Token {
		/// A signal that sends a Completed event when the lifetime ends.
		fileprivate let ended: Signal<(), NoError>

		private let endedObserver: Signal<(), NoError>.Observer

		public init() {
			(ended, endedObserver) = Signal.pipe()
		}

		deinit {
			endedObserver.sendCompleted()
		}
	}
}
