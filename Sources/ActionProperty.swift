import Result

/// A mutable, observable property that has an optionally failable action
/// associated with the setter.
public final class ActionProperty<Value, ActionError: Error>: ComposableMutablePropertyProtocol {
	/// The current value of the property.
	public var value: Value {
		get {
			return cache.value
		}
		set {
			rootBox.lock {
				action(newValue)
			}
		}
	}

	/// A SignalProducer that emits the current value of the property, followed by
	/// all subsequent changes.
	public var producer: SignalProducer<Value, NoError> {
		return cache.producer
	}

	/// A Signal that emits all subsequent changes of the property.
	public var signal: Signal<Value, NoError> {
		return cache.signal
	}

	/// The lifetime of the property.
	public let lifetime: Lifetime

	/// Validations that have been made by the property.
	public let validations: Property<Result<(), ActionError>?>

	/// The action associated with the property.
	private let action: (Value) -> Void

	/// The existential box that wraps the synchronization mechanic of the root
	/// property of the composed chain.
	private let rootBox: ActionPropertyBoxBase<()>

	/// The cache which holds the latest value in terms of `Value`.
	private let cache: Property<Value>

	/// Create an `ActionProperty` that presents `inner` as a property of `Value`,
	/// and invoke `body` with the current value of `inner` and the proposed value
	/// whenever the setter is invoked.
	///
	/// If `success` is returned by `body`, the associated value would be
	/// persisted to `inner`. Otherwise, the failure would be emitted by the
	/// `validations` signal.
	///
	/// - parameters:
	///   - inner: The inner property to wrap.
	///   - transform: The value transform for the presentation.
	///   - body: The closure to invoke for any proposed value to `self`.
	public init<M: ComposableMutablePropertyProtocol>(
		_ inner: M,
		transform: @escaping (M.Value) -> Value,
		_ body: @escaping (M.Value, Value) -> Result<M.Value, ActionError>
	) {
		let _validations = MutableProperty<Result<(), ActionError>?>(nil)

		self.lifetime = inner.lifetime
		self.validations = Property(capturing: _validations)
		self.cache = inner.map(transform)
		self.rootBox = ActionPropertyBox(inner)

		action = { input in
			switch body(inner.value, input) {
			case let .success(innerResult):
				inner.value = innerResult
				_validations.value = .success()

			case let .failure(error):
				_validations.value = .failure(error)
			}
		}
	}

	/// Create an `ActionProperty` that presents `inner` as an `ActionProperty` of
	/// `U` value and `E` error, and invoke `body` with the current value of
	/// `inner` and the proposed value whenever the setter is invoked.
	///
	/// If `success` is returned by `body`, the associated value would be
	/// persisted to `inner`. Otherwise, the failure would be emitted by the
	/// `validations` signal.
	///
	/// - parameters:
	///   - inner: The inner property to wrap.
	///   - transform: The value transform for the presentation.
	///   - errorTransform: The error transform for the presentation.
	///   - body: The closure to invoke for any proposed value to `self`.
	public init<U, E: Error>(
		_ inner: ActionProperty<U, E>,
		transform: @escaping (U) -> Value,
		errorTransform: @escaping (E) -> ActionError,
		_ body: @escaping (U, Value) -> Result<U, ActionError>
	) {
		let _validations = MutableProperty<Result<(), ActionError>?>(nil)

		self.lifetime = inner.lifetime
		self.validations = Property(capturing: _validations)
		self.cache = inner.cache.map(transform)
		self.rootBox = inner.rootBox

		inner.validations.producer
			.map { $0?.mapError(errorTransform) }
			.startWithValues { _validations.value = $0 }

		action = { input in
			switch body(inner.cache.value, input) {
			case let .success(innerResult):
				inner.action(innerResult)

			case let .failure(error):
				_validations.value = .failure(error)
			}
		}
	}

	/// Create an `ActionProperty` that invokes `body` with the current value of
	/// `inner` and the proposed value whenever the setter is invoked.
	///
	/// If `success` is returned by `body`, the associated value would be
	/// persisted to `inner`. Otherwise, the failure would be emitted by the
	/// `validations` signal.
	///
	/// - parameters:
	///   - inner: The inner property to wrap.
	///   - body: The closure to invoke for any proposed value to `self`.
	public convenience init<M: ComposableMutablePropertyProtocol>(
		_ inner: M,
		_ body: @escaping (M.Value, M.Value) -> Result<M.Value, ActionError>
	) where M.Value == Value {
		self.init(inner, transform: { $0 }, body)
	}

	/// Create an `ActionProperty` that presents `inner` as an `ActionProperty` of
	/// `U` values and the same error type, and invoke `body` with the current
	/// value of `inner` and the proposed value whenever the setter is invoked.
	///
	/// If `success` is returned by `body`, the associated value would be
	/// persisted to `inner`. Otherwise, the failure would be emitted by the
	/// `validations` signal.
	///
	/// - parameters:
	///   - inner: The inner property to wrap.
	///   - transform: The value transform for the presentation.
	///   - body: The closure to invoke for any proposed value to `self`.
	public convenience init<U>(
		_ inner: ActionProperty<U, ActionError>,
		transform: @escaping (U) -> Value,
		_ body: @escaping (U, Value) -> Result<U, ActionError>
	) {
		self.init(inner, transform: transform, errorTransform: { $0 }, body)
	}

	/// Create an `ActionProperty` that presents `inner` as an `ActionProperty` of
	/// the same value type and `E` errors, and invoke `body` with the current
	/// value of `inner` and the proposed value whenever the setter is invoked.
	///
	/// If `success` is returned by `body`, the associated value would be
	/// persisted to `inner`. Otherwise, the failure would be emitted by the
	/// `validations` signal.
	///
	/// - parameters:
	///   - inner: The inner property to wrap.
	///   - errorTransform: The error transform for the presentation.
	///   - body: The closure to invoke for any proposed value to `self`.
	public convenience init<E: Swift.Error>(
		_ inner: ActionProperty<Value, E>,
		errorTransform: @escaping (E) -> ActionError,
		_ body: @escaping (Value, Value) -> Result<Value, ActionError>
	) {
		self.init(inner, transform: { $0 }, errorTransform: errorTransform, body)
	}

	/// Atomically performs an arbitrary action using the current value of the
	/// variable.
	///
	/// - parameters:
	///   - action: A closure that accepts current property value.
	///
	/// - returns: the result of the action.
	public func withValue<Result>(action: (Value) throws -> Result) rethrows -> Result {
		return try rootBox.lock {
			return try action(cache.value)
		}
	}

	/// Atomically modifies the variable.
	///
	/// - parameters:
	///   - action: A closure that takes the current value.
	///
	/// - returns: The result of the action.
	public func modify<Result>(_ action: (inout Value) throws -> Result) rethrows -> Result {
		return try rootBox.lock {
			return try action(&value)
		}
	}
}

// FIXME: Remove the type parameter that works around type checker weirdness.
private class ActionPropertyBox<Property: ComposableMutablePropertyProtocol>: ActionPropertyBoxBase<()> {
	private let base: Property

	init(_ base: Property) { self.base = base }

	override func lock<R>(_ action: (()) throws -> R) rethrows -> R {
		return try base.withValue { _ in return try action(()) }
	}
}

private class ActionPropertyBoxBase<Value> {
	func lock<R>(_ action: (()) throws -> R) rethrows -> R {
		fatalError()
	}
}

extension ComposableMutablePropertyProtocol {
	// - The default `map` with `NoError`.

	/// Create a mutable mapped view to `self`.
	///
	/// - parameters:
	///   - forward: The value transform to convert `Self.Value` to `U`.
	///   - backward: The value transform to convert `U` to `Self.Value`.
	///
	/// - returns: A mapping `ActionProperty`.
	public func map<U>(
		forward: @escaping (Value) -> U,
		backward: @escaping (U) -> Value
	) -> ActionProperty<U, NoError> {
		return ActionProperty<U, NoError>(self, transform: forward) { _, proposedInput in
			return .success(backward(proposedInput))
		}
	}

	// - The failable `map` with parameter `Error`.

	/// Create a mutable mapped view to `self` with a failable setter.
	///
	/// - parameters:
	///   - forward: The value transform to convert `Self.Value` to `U`.
	///   - attemptBackward: The failable value transform to convert `U` to
	///                      `Self.Value`.
	///
	/// - returns: A mapping `ActionProperty`.
	public func map<U, Error: Swift.Error>(
		forward: @escaping (Value) -> U,
		attemptBackward: @escaping (U) -> Result<Value, Error>
	) -> ActionProperty<U, Error> {
		return ActionProperty<U, Error>(self, transform: forward) { _, proposedInput in
			return attemptBackward(proposedInput)
		}
	}

	// - The default `validate` with parameter `Error`.

	/// Create a mutable view to `self` that validates any proposed value.
	///
	/// - parameters:
	///   - predicate: The closure that validates any proposed value to the
	///                property.
	///
	/// - returns: A validating `ActionProperty`.
	public func validate<Error: Swift.Error>(
		_ predicate: @escaping (Value) -> Result<(), Error>
	) -> ActionProperty<Value, Error> {
		return ActionProperty(self) { current, proposedInput in
			switch predicate(proposedInput) {
			case .success:
				return .success(proposedInput)

			case let .failure(error):
				return .failure(error)
			}
		}
	}
}

extension ActionProperty {
	// - The overriding `map` that invokes the `ActionProperty` specialization of
	//   `ActionProperty.init`.

	/// Create a mutable mapped view to `self`.
	///
	/// - parameters:
	///   - forward: The value transform to convert `Self.Value` to `U`.
	///   - backward: The value transform to convert `U` to `Self.Value`.
	///
	/// - returns: A mapping `ActionProperty`.
	public func map<U>(
		forward: @escaping (Value) -> U,
		backward: @escaping (U) -> Value
	) -> ActionProperty<U, ActionError> {
		return ActionProperty<U, ActionError>(self, transform: forward) { _, proposedInput in
			return .success(backward(proposedInput))
		}
	}

	// - The overriding failable `map` that invokes the `ActionProperty`
	//   specialization of `ActionProperty.init`.

	/// Create a mutable mapped view to `self` with a failable setter.
	///
	/// - parameters:
	///   - forward: The value transform to convert `Self.Value` to `U`.
	///   - attemptBackward: The failable value transform to convert `U` to
	///                      `Self.Value`.
	///
	/// - returns: A mapping `ActionProperty`.
	public func map<U>(
		forward: @escaping (Value) -> U,
		attemptBackward: @escaping (U) -> Result<Value, ActionError>
	) -> ActionProperty<U, ActionError> {
		typealias ActionProperty = ReactiveSwift.ActionProperty<U, ActionError>
		return ActionProperty(self, transform: forward) { _, proposedInput in
			return attemptBackward(proposedInput)
		}
	}

	// - The failable `map` that supports a different outer error type.

	/// Create a mutable mapped view to `self` with a failable setter.
	///
	/// - parameters:
	///   - forward: The value transform to convert `Self.Value` to `U`.
	///   - attemptBackward: The failable value transform to convert `U` to
	///                      `Self.Value`.
	///
	/// - returns: A mapping `ActionProperty`.
	public func map<U, E: Swift.Error>(
		forward: @escaping (Value) -> U,
		attemptBackward: @escaping (U) -> Result<Value, E>
	) -> ActionProperty<U, Error2<E, ActionError>> {
		typealias ActionProperty = ReactiveSwift.ActionProperty<U, Error2<E, ActionError>>
		return ActionProperty(self, transform: forward) { _, proposedInput in
			switch attemptBackward(proposedInput) {
			case let .success(value):
				return .success(value)

			case let .failure(error):
				return .failure(.outer(error))
			}
		}
	}

	// - The overriding `validate` that invokes the `ActionProperty`
	//   specialization of `ActionProperty.init`.

	/// Create a mutable view to `self` that validates any proposed value.
	///
	/// - parameters:
	///   - predicate: The closure that validates any proposed value to the
	///                property.
	///
	/// - returns: A validating `ActionProperty`.
	public func validate(
		_ predicate: @escaping (Value) -> Result<(), ActionError>
	) -> ActionProperty<Value, ActionError> {
		return ActionProperty(self) { current, proposedInput in
			switch predicate(proposedInput) {
			case .success:
				return .success(proposedInput)

			case let .failure(error):
				return .failure(error)
			}
		}
	}

	// - The `validate` that supports a different outer error type.

	/// Create a mutable view to `self` that validates any proposed value.
	///
	/// - parameters:
	///   - predicate: The closure that validates any proposed value to the
	///                property.
	///
	/// - returns: A validating `ActionProperty`.
	public func validate<Error: Swift.Error>(
		_ predicate: @escaping (Value) -> Result<(), Error>
	) -> ActionProperty<Value, Error2<Error, ActionError>> {
		typealias ActionProperty = ReactiveSwift.ActionProperty<Value, Error2<Error, ActionError>>
		return ActionProperty(self, errorTransform: { .inner($0) }) { current, proposedInput in
			switch predicate(proposedInput) {
			case .success:
				return .success(proposedInput)

			case let .failure(error):
				return .failure(.outer(error))
			}
		}
	}
}

public enum Error2<OuterError: Error, InnerError: Error>: Error {
	case outer(OuterError)
	case inner(InnerError)
}
