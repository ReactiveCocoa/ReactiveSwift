import Result

/// A mutable, observable property that has an optionally failable action
/// associated with the setter.
///
/// ## Consistency when nested
///
/// `TransactionalProperty` would back-propagate the validation failure if a
/// proposed value from an outer property fails with its inner property.
///
/// It would also evaluate values originated from the inner property. In other
/// words, it is possible for `value` to be invalid, causing `validations`
/// to be a `failure`. Rely on `validations` for asserting a pass in validation.
public final class TransactionalProperty<Value, TransactionError: Error>: ComposableMutablePropertyProtocol {
	/// The current value of the property.
	///
	/// It does not guarantee that the value is valid with regard to `self`, since
	/// changes might be initiated from the inner properties. Check `validations`
	/// for the latest validation state.
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
	public let validations: Property<ValidationResult<Value, TransactionError>>

	/// The action associated with the property.
	private let action: (Value) -> Void

	/// The existential box that wraps the synchronization mechanic of the root
	/// property of the composed chain.
	private let rootBox: TransactionalPropertyBoxBase<()>

	/// The cache which holds the latest value in terms of `Value`.
	private let cache: Property<Value>

	/// Create an `TransactionalProperty` that presents `inner` as a property of
	/// `Value`, and invoke `body` with the proposed value whenever the setter is
	/// invoked.
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
		_ body: @escaping (Value) -> Result<M.Value, TransactionError>
	) {
		var mutesValueBackpropagation = false

		let _validations: MutableProperty<ValidationResult<Value, TransactionError>> = inner.withValue { innerValue in
			let property = MutableProperty(ValidationResult(innerValue, transform: transform, validator: body))

			property <~ inner.signal
				.filter { _ in !mutesValueBackpropagation }
				.map { ValidationResult($0, transform: transform, validator: body) }

			return property
		}

		self.validations = Property(capturing: _validations)
		self.lifetime = inner.lifetime
		self.cache = inner.map(transform)
		self.rootBox = TransactionalPropertyBox(inner)

		action = { input in
			switch body(input) {
			case let .success(innerResult):
				mutesValueBackpropagation = true
				inner.value = innerResult
				_validations.value = .success(input)
				mutesValueBackpropagation = false

			case let .failure(error):
				_validations.value = .failure(input, error)
			}
		}
	}

	/// Create an `TransactionalProperty` that presents `inner` as an
	/// `TransactionalProperty` of `U` value, and invoke `body` with the proposed
	/// value whenever the setter is invoked.
	///
	/// If `success` is returned by `body`, the associated value would be
	/// persisted to `inner`. Otherwise, the failure would be emitted by the
	/// `validations` signal.
	///
	/// The validation results of `inner` would be propagated to the created
	/// `TransactionalProperty`.
	///
	/// - parameters:
	///   - inner: The inner property to wrap.
	///   - transform: The value transform for the presentation.
	///   - errorTransform: The error transform for the presentation.
	///   - body: The closure to invoke for any proposed value to `self`.
	public convenience init<T: _TransactionalPropertyProtocol>(
		_ inner: T,
		transform: @escaping (T.Value) -> Value,
		errorTransform: @escaping (T.TransactionError) -> TransactionError,
		_ body: @escaping (Value) -> Result<T.Value, TransactionError>
	) {
		self.init(inner, transform: transform, validator: body, validationSetup: { validations in
			validations <~ inner.property.validations.signal
				.map { $0.map(transform, errorTransform, validator: body) }
		})
	}

	/// Create an `TransactionalProperty` that presents `inner` as an
	/// `TransactionalProperty` of `U` value, and invoke `body` with the proposed
	/// value whenever the setter is invoked.
	///
	/// If `success` is returned by `body`, the associated value would be
	/// persisted to `inner`. Otherwise, the failure would be emitted by the
	/// `validations` signal.
	///
	/// - parameters:
	///   - inner: The inner property to wrap.
	///   - transform: The value transform for the presentation.
	///   - body: The closure to invoke for any proposed value to `self`.
	public convenience init<T: _TransactionalPropertyProtocol>(
		_ inner: T,
		transform: @escaping (T.Value) -> Value,
		_ body: @escaping (Value) -> Result<T.Value, TransactionError>
	) where T.TransactionError == NoError {
		self.init(inner, transform: transform, validator: body, validationSetup: nil)
	}

	private init<T: _TransactionalPropertyProtocol>(
		_ inner: T,
		transform: @escaping (T.Value) -> Value,
		validator: @escaping (Value) -> Result<T.Value, TransactionError>,
		validationSetup: ((MutableProperty<ValidationResult<Value, TransactionError>>) -> Void)?
	) {
		let _validations: MutableProperty<ValidationResult<Value, TransactionError>> = inner.withValue { innerValue in
			let property = MutableProperty(ValidationResult(innerValue, transform: transform, validator: validator))
			validationSetup?(property)
			return property
		}

		self.validations = Property(capturing: _validations)
		self.lifetime = inner.lifetime
		self.cache = inner.property.cache.map(transform)
		self.rootBox = inner.property.rootBox


		action = { input in
			switch validator(input) {
			case let .success(innerResult):
				inner.property.action(innerResult)

			case let .failure(error):
				_validations.value = .failure(input, error)
			}
		}
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

	internal func revalidate() {
		rootBox.lock {
			action(cache.value)
		}
	}
}

public protocol _TransactionalPropertyProtocol: ComposableMutablePropertyProtocol {
	associatedtype Value
	associatedtype TransactionError: Swift.Error

	var property: TransactionalProperty<Value, TransactionError> { get }

	init<T: _TransactionalPropertyProtocol>(
		_ inner: T,
		transform: @escaping (T.Value) -> Value,
		errorTransform: @escaping (T.TransactionError) -> TransactionError,
		_ body: @escaping (Value) -> Result<T.Value, TransactionError>
	)

	init<T: _TransactionalPropertyProtocol>(
		_ inner: T,
		transform: @escaping (T.Value) -> Value,
		_ body: @escaping (Value) -> Result<T.Value, TransactionError>
	) where T.TransactionError == NoError
}

extension TransactionalProperty: _TransactionalPropertyProtocol {
	public var property: TransactionalProperty<Value, TransactionError> {
		return self
	}
}

public enum ValidationResult<Value, Error: Swift.Error> {
	case success(Value)
	case failure(Value, Error)

	public var isFailed: Bool {
		if case .failure = self {
			return true
		} else {
			return false
		}
	}

	public var error: Error? {
		if case let .failure(_, error) = self {
			return error
		} else {
			return nil
		}
	}

	public var result: Result<Value, Error> {
		switch self {
		case let .success(value):
			return .success(value)
		case let .failure(_, error):
			return .failure(error)
		}
	}

	fileprivate init<InnerValue>(_ innerValue: InnerValue, transform: (InnerValue) -> Value, validator: (Value) -> Result<InnerValue, Error>) {
		let value = transform(innerValue)

		switch validator(value) {
		case .success:
			self = .success(value)
		case let .failure(error):
			self = .failure(value, error)
		}
	}

	public func map<U, E: Swift.Error>(_ transform: (Value) -> U, _ errorTransform: (Error) -> E, validator: (U) -> Result<Value, E>) -> ValidationResult<U, E> {
		switch self {
		case let .success(value):
			switch validator(transform(value)) {
			case let .success(innerValue):
				return .success(transform(innerValue))
			case let .failure(error):
				return .failure(transform(value), error)
			}

		case let .failure(value, error):
			return .failure(transform(value), errorTransform(error))
		}
	}
}

// FIXME: Remove the type parameter that works around type checker weirdness.
private class TransactionalPropertyBox<Property: ComposableMutablePropertyProtocol>: TransactionalPropertyBoxBase<()> {
	private let base: Property

	init(_ base: Property) { self.base = base }

	override func lock<R>(_ action: (()) throws -> R) rethrows -> R {
		return try base.withValue { _ in return try action(()) }
	}
}

private class TransactionalPropertyBoxBase<Value> {
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
	/// - returns: A mapping `TransactionalProperty`.
	public func map<U>(
		forward: @escaping (Value) -> U,
		backward: @escaping (U) -> Value
	) -> TransactionalProperty<U, NoError> {
		return TransactionalProperty(self, transform: forward) { proposedInput in
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
	/// - returns: A mapping `TransactionalProperty`.
	public func map<U, Error: Swift.Error>(
		forward: @escaping (Value) -> U,
		attemptBackward: @escaping (U) -> Result<Value, Error>
	) -> TransactionalProperty<U, Error> {
		return TransactionalProperty<U, Error>(self, transform: forward) { proposedInput in
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
	/// - returns: A validating `TransactionalProperty`.
	public func validate<Error: Swift.Error>(
		_ predicate: @escaping (Value) -> Result<(), Error>
	) -> TransactionalProperty<Value, Error> {
		return TransactionalProperty(self, transform: { $0 }) { proposedInput in
			switch predicate(proposedInput) {
			case .success:
				return .success(proposedInput)

			case let .failure(error):
				return .failure(error)
			}
		}
	}

	// - The default `validate(with:)` with parameter `Error`.

	/// Create a mutable view to `self` that validates any proposed value in
	/// consideration of `other`.
	///
	/// If `self` has failed the predicate and `other` changes subsequently, the
	/// predicate would be reevaluated automatically.
	///
	/// - parameters:
	///   - other: The property the validation logic depends on.
	///   - predicate: The closure that validates any proposed value to the
	///                property.
	///
	/// - returns: A validating `TransactionalProperty`.
	public func validate<P: PropertyProtocol, Error: Swift.Error>(
		with other: P,
		_ predicate: @escaping (Value, P.Value) -> Result<(), Error>
	) -> TransactionalProperty<Value, Error> {
		return TransactionalProperty<Value, Error>
			.validate({ TransactionalProperty(self, transform: { $0 }, $0) }, with: other, predicate)
	}

	// - The default `validate(with:)` with parameter `Error`.

	/// Create a mutable view to `self` that validates any proposed value in
	/// consideration of `other`.
	///
	/// If `self` has failed the predicate and `other` changes subsequently, the
	/// predicate would be reevaluated automatically.
	///
	/// - parameters:
	///   - other: The property the validation logic depends on.
	///   - predicate: The closure that validates any proposed value to the
	///                property.
	///
	/// - returns: A validating `TransactionalProperty`.
	public func validate<P: _TransactionalPropertyProtocol, Error: Swift.Error>(
		with other: P,
		_ predicate: @escaping (Value, P.Value) -> Result<(), Error>
	) -> TransactionalProperty<Value, Error> {
		return TransactionalProperty<Value, Error>
			.validate({ TransactionalProperty(self, transform: { $0 }, $0) }, with: other, predicate)
	}
}

extension _TransactionalPropertyProtocol {
	fileprivate static func validate<Other: PropertyProtocol, E: Swift.Error>(
		_ initializer: (@escaping (Value) -> Result<Value, E>) -> TransactionalProperty<Value, E>,
		with other: Other,
		_ validator: @escaping (Value, Other.Value) -> Result<(), E>
	) -> TransactionalProperty<Value, E> {
		let other = Property(other)

		let property = initializer { proposedInput -> Result<Value, E> in
			return validator(proposedInput, other.value).map { _ in proposedInput }
		}

		let d = other.signal.observeValues { [weak property] _ in
			if let property = property {
				if case let .failure(failedValue, _) = property.validations.value {
					property.value = failedValue
				} else {
					property.property.revalidate()
				}
			}
		}

		property.lifetime.ended.observeCompleted { d?.dispose() }

		return property
	}

	fileprivate static func validate<Other: _TransactionalPropertyProtocol, E: Swift.Error>(
		_ initializer: (@escaping (Value) -> Result<Value, E>) -> TransactionalProperty<Value, E>,
		with other: Other,
		_ validator: @escaping (Value, Other.Value) -> Result<(), E>
	) -> TransactionalProperty<Value, E> {
		let otherValidations = other.property.validations

		let property = initializer { proposedInput -> Result<Value, E> in
			let otherValue: Other.Value

			switch otherValidations.value {
			case let .success(value):
				otherValue = value
			case let .failure(value, _):
				otherValue = value
			}

			return validator(proposedInput, otherValue).map { _ in proposedInput }
		}

		let d = otherValidations.signal.observeValues { [weak property] _ in
			if let property = property {
				if case let .failure(failedValue, _) = property.validations.value {
					property.value = failedValue
				} else {
					property.property.revalidate()
				}
			}
		}

		property.lifetime.ended.observeCompleted { d?.dispose() }

		return property
	}
}

extension _TransactionalPropertyProtocol {
	// - The overriding `map` that invokes the `TransactionalProperty`
	//   specialization of `TransactionalProperty.init`.

	/// Create a mutable mapped view to `self`.
	///
	/// - parameters:
	///   - forward: The value transform to convert `Self.Value` to `U`.
	///   - backward: The value transform to convert `U` to `Self.Value`.
	///
	/// - returns: A mapping `TransactionalProperty`.
	public func map<U>(
		forward: @escaping (Value) -> U,
		backward: @escaping (U) -> Value
	) -> TransactionalProperty<U, TransactionError> {
		return TransactionalProperty(self, transform: forward) { proposedInput in
			return .success(backward(proposedInput))
		}
	}

	// - The overriding failable `map` that invokes the `TransactionalProperty`
	//   specialization of `TransactionalProperty.init`.
	/// Create a mutable mapped view to `self` with a failable setter.
	///
	/// - parameters:
	///   - forward: The value transform to convert `Self.Value` to `U`.
	///   - attemptBackward: The failable value transform to convert `U` to
	///                      `Self.Value`.
	///
	/// - returns: A mapping `TransactionalProperty`.
	public func map<U>(
		forward: @escaping (Value) -> U,
		attemptBackward: @escaping (U) -> Result<Value, TransactionError>
	) -> TransactionalProperty<U, TransactionError> {
		return TransactionalProperty(self, transform: forward, errorTransform: { $0 }) { proposedInput in
			return attemptBackward(proposedInput)
		}
	}

	// - The overriding `validate` that invokes the `TransactionalProperty`
	//   specialization of `TransactionalProperty.init`.

	/// Create a mutable view to `self` that validates any proposed value.
	///
	/// - parameters:
	///   - predicate: The closure that validates any proposed value to the
	///                property.
	///
	/// - returns: A validating `TransactionalProperty`.
	public func validate(
		_ predicate: @escaping (Value) -> Result<(), TransactionError>
	) -> TransactionalProperty<Value, TransactionError> {
		return TransactionalProperty(self, transform: { $0 }, errorTransform: { $0 }) { proposedInput in
			switch predicate(proposedInput) {
			case .success:
				return .success(proposedInput)

			case let .failure(error):
				return .failure(error)
			}
		}
	}

	// - The overriding `validate(with:)` that invokes the `TransactionalProperty`
	//   specialization of `TransactionalProperty.init`.

	/// Create a mutable view to `self` that validates any proposed value in
	/// consideration of `other`.
	///
	/// If `self` has failed the predicate and `other` changes subsequently, the
	/// predicate would be reevaluated automatically.
	///
	/// - parameters:
	///   - other: The property the validation logic depends on.
	///   - predicate: The closure that validates any proposed value to the
	///                property.
	///
	/// - returns: A validating `TransactionalProperty`.
	public func validate<P: PropertyProtocol>(
		with other: P,
		_ predicate: @escaping (Value, P.Value) -> Result<(), TransactionError>
	) -> TransactionalProperty<Value, TransactionError> {
		return TransactionalProperty<Value, TransactionError>
			.validate({ TransactionalProperty(self, transform: { $0 }, errorTransform: { $0 }, $0) },
			          with: other,
			          predicate)
	}

	// - The overriding `validate(with:)` that invokes the `TransactionalProperty`
	//   specialization of `TransactionalProperty.init`.

	/// Create a mutable view to `self` that validates any proposed value in
	/// consideration of `other`.
	///
	/// If `self` has failed the predicate and `other` changes subsequently, the
	/// predicate would be reevaluated automatically.
	///
	/// - parameters:
	///   - other: The property the validation logic depends on.
	///   - predicate: The closure that validates any proposed value to the
	///                property.
	///
	/// - returns: A validating `TransactionalProperty`.
	public func validate<P: _TransactionalPropertyProtocol>(
		with other: P,
		_ predicate: @escaping (Value, P.Value) -> Result<(), TransactionError>
	) -> TransactionalProperty<Value, TransactionError> {
		return TransactionalProperty<Value, TransactionError>
			.validate({ TransactionalProperty(self, transform: { $0 }, errorTransform: { $0 }, $0) },
			          with: other,
			          predicate)
	}
}

extension _TransactionalPropertyProtocol where TransactionError == NoError {
	// - The overriding failable `map` that invokes the `TransactionalProperty`
	//   specialization of `TransactionalProperty.init`.
	/// Create a mutable mapped view to `self` with a failable setter.
	///
	/// - parameters:
	///   - forward: The value transform to convert `Self.Value` to `U`.
	///   - attemptBackward: The failable value transform to convert `U` to
	///                      `Self.Value`.
	///
	/// - returns: A mapping `TransactionalProperty`.
	public func map<U, NewError: Swift.Error>(
		forward: @escaping (Value) -> U,
		attemptBackward: @escaping (U) -> Result<Value, NewError>
	) -> TransactionalProperty<U, NewError> {
		return TransactionalProperty(self, transform: forward) { proposedInput in
			return attemptBackward(proposedInput)
		}
	}

	// - The overriding `validate` that invokes the `TransactionalProperty`
	//   specialization of `TransactionalProperty.init`.

	/// Create a mutable view to `self` that validates any proposed value.
	///
	/// - parameters:
	///   - predicate: The closure that validates any proposed value to the
	///                property.
	///
	/// - returns: A validating `TransactionalProperty`.
	public func validate<NewError: Swift.Error>(
		_ predicate: @escaping (Value) -> Result<(), NewError>
	) -> TransactionalProperty<Value, NewError> {
		return TransactionalProperty(self, transform: { $0 }) { proposedInput in
			switch predicate(proposedInput) {
			case .success:
				return .success(proposedInput)

			case let .failure(error):
				return .failure(error)
			}
		}
	}

	// - The overriding `validate(with:)` that invokes the `TransactionalProperty`
	//   specialization of `TransactionalProperty.init`.

	/// Create a mutable view to `self` that validates any proposed value in
	/// consideration of `other`.
	///
	/// If `self` has failed the predicate and `other` changes subsequently, the
	/// predicate would be reevaluated automatically.
	///
	/// - parameters:
	///   - other: The property the validation logic depends on.
	///   - predicate: The closure that validates any proposed value to the
	///                property.
	///
	/// - returns: A validating `TransactionalProperty`.
	public func validate<P: PropertyProtocol, NewError: Swift.Error>(
		with other: P,
		_ predicate: @escaping (Value, P.Value) -> Result<(), NewError>
	) -> TransactionalProperty<Value, NewError> {
		return TransactionalProperty<Value, NewError>
			.validate({ TransactionalProperty(self, transform: { $0 }, $0) },
			          with: other,
			          predicate)
	}

	// - The overriding `validate(with:)` that invokes the `TransactionalProperty`
	//   specialization of `TransactionalProperty.init`.

	/// Create a mutable view to `self` that validates any proposed value in
	/// consideration of `other`.
	///
	/// If `self` has failed the predicate and `other` changes subsequently, the
	/// predicate would be reevaluated automatically.
	///
	/// - parameters:
	///   - other: The property the validation logic depends on.
	///   - predicate: The closure that validates any proposed value to the
	///                property.
	///
	/// - returns: A validating `TransactionalProperty`.
	public func validate<P: _TransactionalPropertyProtocol, NewError: Swift.Error>(
		with other: P,
		_ predicate: @escaping (Value, P.Value) -> Result<(), NewError>
	) -> TransactionalProperty<Value, NewError> {
		return TransactionalProperty<Value, NewError>
			.validate({ TransactionalProperty(self, transform: { $0 }, $0) },
			          with: other,
			          predicate)
	}
}
