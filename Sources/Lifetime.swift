import Foundation
import enum Result.NoError

/// Describes a reference type which provides a lifetime.
public protocol LifetimeProvider: class {
	var lifetime: Lifetime { get }
}

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

extension LifetimeProvider {
	/// Lifts the method on `self` into the reactive world. When attached to a 
	/// signal, the method would be invoked whenever the signal sends a `value`
	/// event.
	///
	/// - note: `self` would be weakly referenced.
	///
	/// - parameters:
	///   - transform: The transform to extract the method to be lifted from
	///                `self`.
	///
	/// - returns: A generator closure which accepts a signal for attaching the
	///            lifted method to.
	public func lift<A>(
		_ transform: @escaping (Self) -> (A) -> Void
	) -> (Signal<A, NoError>) -> Void {
		return { signal in
			signal
				.take(during: self.lifetime)
				.observeValues { [weak self] in self.map(transform)?($0) }
		}
	}

	/// Lifts the method on `self` into the reactive world. When attached to a
	/// signal, the method would be invoked whenever the signal sends a `value`
	/// event.
	///
	/// - note: `self` would be weakly referenced.
	///
	/// - parameters:
	///   - transform: The transform to extract the method to be lifted from
	///                `self`.
	///
	/// - returns: A generator closure which accepts a signal for attaching the
	///            lifted method to.
	public func lift<A, B>(
		_ transform: @escaping (Self) -> (A, B) -> Void
	) -> (Signal<(A, B), NoError>) -> Void {
		return { signal in
			signal
				.take(during: self.lifetime)
				.observeValues { [weak self] in self.map(transform)?($0, $1) }
		}
	}

	/// Lifts the method on `self` into the reactive world. When attached to a
	/// signal, the method would be invoked whenever the signal sends a `value`
	/// event.
	///
	/// - note: `self` would be weakly referenced.
	///
	/// - parameters:
	///   - transform: The transform to extract the method to be lifted from
	///                `self`.
	///
	/// - returns: A generator closure which accepts a signal for attaching the
	///            lifted method to.
	public func lift<A, B, C>(
		_ transform: @escaping (Self) -> (A, B, C) -> Void
	) -> (Signal<(A, B, C), NoError>) -> Void {
		return { signal in
			signal
				.take(during: self.lifetime)
				.observeValues { [weak self] in self.map(transform)?($0, $1, $2) }
		}
	}

	/// Lifts the method on `self` into the reactive world. When attached to a
	/// signal, the method would be invoked whenever the signal sends a `value`
	/// event.
	///
	/// - note: `self` would be weakly referenced.
	///
	/// - parameters:
	///   - transform: The transform to extract the method to be lifted from
	///                `self`.
	///
	/// - returns: A generator closure which accepts a signal for attaching the
	///            lifted method to.
	public func lift<A, B, C, D>(
		_ transform: @escaping (Self) -> (A, B, C, D) -> Void
	) -> (Signal<(A, B, C, D), NoError>) -> Void {
		return { signal in
			signal
				.take(during: self.lifetime)
				.observeValues { [weak self] in self.map(transform)?($0, $1, $2, $3) }
		}
	}

	/// Lifts the method on `self` into the reactive world. When attached to a
	/// signal, the method would be invoked whenever the signal sends a `value`
	/// event.
	///
	/// - note: `self` would be weakly referenced.
	///
	/// - parameters:
	///   - transform: The transform to extract the method to be lifted from
	///                `self`.
	///
	/// - returns: A generator closure which accepts a signal for attaching the
	///            lifted method to.
	public func lift<A, B, C, D, E>(
		_ transform: @escaping (Self) -> (A, B, C, D, E) -> Void
	) -> (Signal<(A, B, C, D, E), NoError>) -> Void {
		return { signal in
			signal
				.take(during: self.lifetime)
				.observeValues { [weak self] in self.map(transform)?($0, $1, $2, $3, $4) }
		}
	}

	/// Lifts the method on `self` into the reactive world. When attached to a
	/// signal, the method would be invoked whenever the signal sends a `value`
	/// event.
	///
	/// - note: `self` would be weakly referenced.
	///
	/// - parameters:
	///   - transform: The transform to extract the method to be lifted from
	///                `self`.
	///
	/// - returns: A generator closure which accepts a signal for attaching the
	///            lifted method to.
	public func lift<A, B, C, D, E, F>(
		_ transform: @escaping (Self) -> (A, B, C, D, E, F) -> Void
	) -> (Signal<(A, B, C, D, E, F), NoError>) -> Void {
		return { signal in
			signal
				.take(during: self.lifetime)
				.observeValues { [weak self] in self.map(transform)?($0, $1, $2, $3, $4, $5) } }
	}
}
