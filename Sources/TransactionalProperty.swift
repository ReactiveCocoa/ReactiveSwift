import Result

/// A mutable, observable property that has an optionally failable action
/// associated with the setter.
public final class TransactionalProperty<Value, TransactionError: Error>: ComposableMutablePropertyProtocol {
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
	public let validations: Property<Result<(), TransactionError>>

	/// The action associated with the property.
	private let action: (Value) -> Void

	/// The existential box that wraps the synchronization mechanic of the root
	/// property of the composed chain.
	private let rootBox: TransactionalPropertyBoxBase<()>

	/// The cache which holds the latest value in terms of `Value`.
	private let cache: Property<Value>

	/// Create an `TransactionalProperty` that presents `inner` as a property of
	/// `Value`, and invoke `body` with the current value of `inner` and the
	/// proposed value whenever the setter is invoked.
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
		_ body: @escaping (M.Value, Value) -> Result<M.Value, TransactionError>
	) {
		let current = inner.value
		let initialValidation = body(current, transform(current)).map { _ in }
		let _validations = MutableProperty<Result<(), TransactionError>>(initialValidation)

		self.lifetime = inner.lifetime
		self.validations = Property(capturing: _validations)
		self.cache = inner.map(transform)
		self.rootBox = TransactionalPropertyBox(inner)

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

	/// Create an `TransactionalProperty` that presents `inner` as an
	/// `TransactionalProperty` of `U` value and `E` error, and invoke `body` with
	/// the current value of `inner` and the proposed value whenever the setter is
	/// invoked.
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
		_ inner: TransactionalProperty<U, E>,
		transform: @escaping (U) -> Value,
		errorTransform: @escaping (E) -> TransactionError,
		_ body: @escaping (U, Value) -> Result<U, TransactionError>
	) {
		let current = inner.value
		let initialValidation = body(current, transform(current)).map { _ in }
		let _validations = MutableProperty<Result<(), TransactionError>>(initialValidation)

		self.lifetime = inner.lifetime
		self.validations = Property(capturing: _validations)
		self.cache = inner.cache.map(transform)
		self.rootBox = inner.rootBox

		let d = _validations <~ inner.validations.producer.map { $0.mapError(errorTransform) }
		_validations.lifetime.ended.observeCompleted { d?.dispose() }

		action = { input in
			switch body(inner.cache.value, input) {
			case let .success(innerResult):
				inner.action(innerResult)

			case let .failure(error):
				_validations.value = .failure(error)
			}
		}
	}

	/// Create an `TransactionalProperty` that invokes `body` with the current value of
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
		_ body: @escaping (M.Value, M.Value) -> Result<M.Value, TransactionError>
	) where M.Value == Value {
		self.init(inner, transform: { $0 }, body)
	}

	/// Create an `TransactionalProperty` that presents `inner` as an
	/// `TransactionalProperty` of `U` values and the same error type, and invoke
	/// `body` with the current value of `inner` and the proposed value whenever
	/// the setter is invoked.
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
		_ inner: TransactionalProperty<U, TransactionError>,
		transform: @escaping (U) -> Value,
		_ body: @escaping (U, Value) -> Result<U, TransactionError>
	) {
		self.init(inner, transform: transform, errorTransform: { $0 }, body)
	}

	/// Create an `TransactionalProperty` that presents `inner` as an
	/// `TransactionalProperty` of the same value type and `E` errors, and invoke
	/// `body` with the current value of `inner` and the proposed value whenever
	/// the setter is invoked.
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
		_ inner: TransactionalProperty<Value, E>,
		errorTransform: @escaping (E) -> TransactionError,
		_ body: @escaping (Value, Value) -> Result<Value, TransactionError>
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

	internal func revalidate() {
		rootBox.lock {
			action(cache.value)
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
		return TransactionalProperty<U, NoError>(self, transform: forward) { _, proposedInput in
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
		return TransactionalProperty<U, Error>(self, transform: forward) { _, proposedInput in
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
		return TransactionalProperty(self) { current, proposedInput in
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
	///   - predicate: The closure that validates any proposed value to the
	///                property.
	///
	/// - returns: A validating `TransactionalProperty`.
	public func validate<P: PropertyProtocol, Error: Swift.Error>(
		with other: P,
		_ predicate: @escaping (Value, P.Value) -> Result<(), Error>
	) -> TransactionalProperty<Value, Error> {
		return TransactionalProperty<Value, Error>
			.validate({ TransactionalProperty(self, $0) }, with: other, predicate)
	}
}

extension TransactionalProperty {
	// Shared implementation of `validate(with:)`.
	fileprivate static func validate<Other: PropertyProtocol, Error>(
		_ initializer: (@escaping (Value, Value) -> Result<Value, Error>) -> TransactionalProperty<Value, Error>,
		with other: Other,
		_ predicate: @escaping (Value, Other.Value) -> Result<(), Error>
		) -> TransactionalProperty<Value, Error> {
		let other = Property(other)
		let proposed = Atomic<Value?>(nil)

		let property = initializer { _, proposedInput -> Result<Value, Error> in
			switch predicate(proposedInput, other.value) {
			case .success:
				proposed.value = nil
				return .success(proposedInput)

			case let .failure(error):
				proposed.value = proposedInput
				return .failure(error)
			}
		}

		let d = other.signal.observeValues { [weak property] _ in
			if let value = proposed.swap(nil) {
				property?.value = value
			} else {
				property?.revalidate()
			}
		}

		property.lifetime.ended.observeCompleted { d?.dispose() }

		return property
	}
}

extension TransactionalProperty {
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
		return TransactionalProperty<U, TransactionError>(self, transform: forward) { _, proposedInput in
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
		typealias TransactionalProperty = ReactiveSwift.TransactionalProperty<U, TransactionError>
		return TransactionalProperty(self, transform: forward) { _, proposedInput in
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
		return TransactionalProperty(self) { current, proposedInput in
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
	///   - predicate: The closure that validates any proposed value to the
	///                property.
	///
	/// - returns: A validating `TransactionalProperty`.
	public func validate<P: PropertyProtocol>(
		with other: P,
		_ predicate: @escaping (Value, P.Value) -> Result<(), TransactionError>
	) -> TransactionalProperty<Value, TransactionError> {
		return TransactionalProperty<Value, TransactionError>
			.validate({ TransactionalProperty(self, $0) }, with: other, predicate)
	}
}
