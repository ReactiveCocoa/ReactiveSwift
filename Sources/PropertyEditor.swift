import Result

/// An editor that monitor, validates and commits changes to its root property.
///
/// ## Consistency when nested
///
/// `PropertyEditor` would back-propagate the validation failure if a
/// proposed value from an outer editor fails with its inner property.
///
/// It would also evaluate values originated from the inner property. In other
/// words, it is possible for `value` to be invalid, causing `validations`
/// to be a `failure`. Rely on `validations` for asserting a pass in validation.
public final class PropertyEditor<Value, ValidationError: Error> {
	/// The commited value with regard to the root property of the editor.
	///
	/// It does not guarantee that the value is valid with regard to `self`, since
	/// changes might be initiated from the inner properties. Check `validations`
	/// for the latest validation state.
	public var commited: Property<Value>

	/// The lifetime token of the editor.
	private let lifetimeToken: Lifetime.Token

	/// The lifetime of the editor.
	public let lifetime: Lifetime

	/// The latest validation that have been made by the editor.
	public let result: Property<ValidationResult<Value, ValidationError>>

	/// The action associated with the editor.
	private let action: (Value) -> Void

	/// The existential box that wraps the synchronization mechanic of the root
	/// property of the composed chain.
	private let rootBox: PropertyEditorBoxBase<()>

	/// Create an `PropertyEditor` that presents an editing interface of `inner`
	/// in another value type, using the given forward transform and the given
	/// failable reverse transform.
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
		_ body: @escaping (Value) -> Result<M.Value, ValidationError>
	) {
		var mutesValueBackpropagation = false

		let _validations: MutableProperty<ValidationResult<Value, ValidationError>> = inner.withValue { innerValue in
			let property = MutableProperty(ValidationResult(innerValue, transform: transform, validator: body))

			property <~ inner.signal
				.filter { _ in !mutesValueBackpropagation }
				.map { ValidationResult($0, transform: transform, validator: body) }

			return property
		}

		self.result = Property(capturing: _validations)
		self.lifetimeToken = Lifetime.Token()
		self.lifetime = Lifetime(lifetimeToken)
		self.commited = inner.map(transform)
		self.rootBox = PropertyEditorBox(inner)

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

	/// Create an `PropertyEditor` that presents an editing interface of `inner`
	/// in another value type and error type, using the given forward transform,
	/// the given failable reverse transform, and the given error transform.
	///
	/// If `success` is returned by `body`, the associated value would be
	/// persisted to `inner`. Otherwise, the failure would be emitted by the
	/// `validations` signal.
	///
	/// The validation results of `inner` would be propagated to the created
	/// `PropertyEditor`.
	///
	/// - parameters:
	///   - inner: The inner property to wrap.
	///   - transform: The value transform for the presentation.
	///   - errorTransform: The error transform for the presentation.
	///   - body: The closure to invoke for any proposed value to `self`.
	public convenience init<T: _PropertyEditorProtocol>(
		_ inner: T,
		transform: @escaping (T.Value) -> Value,
		errorTransform: @escaping (T.ValidationError) -> ValidationError,
		_ body: @escaping (Value) -> Result<T.Value, ValidationError>
	) {
		self.init(inner, transform: transform, validator: body, validationSetup: { validations in
			validations <~ inner.property.result.signal
				.map { $0.map(transform, errorTransform, validator: body) }
		})
	}

	/// Create an `PropertyEditor` that presents an editing interface of `inner`
	/// in another value type, using the given forward transform and the given
	/// failable reverse transform.
	///
	/// If `success` is returned by `body`, the associated value would be
	/// persisted to `inner`. Otherwise, the failure would be emitted by the
	/// `validations` signal.
	///
	/// - parameters:
	///   - inner: The inner property to wrap.
	///   - transform: The value transform for the presentation.
	///   - body: The closure to invoke for any proposed value to `self`.
	public convenience init<T: _PropertyEditorProtocol>(
		_ inner: T,
		transform: @escaping (T.Value) -> Value,
		_ body: @escaping (Value) -> Result<T.Value, ValidationError>
	) where T.ValidationError == NoError {
		self.init(inner, transform: transform, validator: body, validationSetup: nil)
	}

	private init<T: _PropertyEditorProtocol>(
		_ inner: T,
		transform: @escaping (T.Value) -> Value,
		validator: @escaping (Value) -> Result<T.Value, ValidationError>,
		validationSetup: ((MutableProperty<ValidationResult<Value, ValidationError>>) -> Void)?
	) {
		let _validations: MutableProperty<ValidationResult<Value, ValidationError>> = inner.property.rootBox.lock {
			let property = MutableProperty(ValidationResult(inner.property.commited.value, transform: transform, validator: validator))
			validationSetup?(property)
			return property
		}

		self.result = Property(capturing: _validations)
		self.lifetimeToken = Lifetime.Token()
		self.lifetime = Lifetime(lifetimeToken)
		self.commited = inner.property.commited.map(transform)
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

	@discardableResult
	public func `try`(_ newValue: Value) {
		rootBox.lock {
			action(newValue)
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
			return try action(commited.value)
		}
	}

	internal func revalidate() {
		rootBox.lock {
			action(commited.value)
		}
	}
}

extension PropertyEditor: BindingTargetProtocol {
	public func consume(_ value: Value) {
		self.try(value)
	}
}

extension PropertyEditor: BindingSourceProtocol {
	public func observe(_ observer: Observer<Value, NoError>, during lifetime: Lifetime) -> Disposable? {
		return commited.producer
			.take(during: lifetime)
			.start(observer)
	}
}

public protocol _PropertyEditorProtocol: class {
	associatedtype Value
	associatedtype ValidationError: Swift.Error

	var property: PropertyEditor<Value, ValidationError> { get }

	init<T: _PropertyEditorProtocol>(
		_ inner: T,
		transform: @escaping (T.Value) -> Value,
		errorTransform: @escaping (T.ValidationError) -> ValidationError,
		_ body: @escaping (Value) -> Result<T.Value, ValidationError>
	)

	init<T: _PropertyEditorProtocol>(
		_ inner: T,
		transform: @escaping (T.Value) -> Value,
		_ body: @escaping (Value) -> Result<T.Value, ValidationError>
	) where T.ValidationError == NoError
}

extension PropertyEditor: _PropertyEditorProtocol {
	public var property: PropertyEditor<Value, ValidationError> {
		return self
	}
}

public enum ValidationResult<Value, Error: Swift.Error> {
	case success(Value)
	case failure(Value, Error)

	public var isFailure: Bool {
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
private class PropertyEditorBox<Property: ComposableMutablePropertyProtocol>: PropertyEditorBoxBase<()> {
	private let base: Property

	init(_ base: Property) { self.base = base }

	override func lock<R>(_ action: (()) throws -> R) rethrows -> R {
		return try base.withValue { _ in return try action(()) }
	}
}

private class PropertyEditorBoxBase<Value> {
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
	///   - reverse: The value transform to convert `U` to `Self.Value`.
	///
	/// - returns: A mapping `PropertyEditor`.
	public func map<U>(
		forward: @escaping (Value) -> U,
		reverse: @escaping (U) -> Value
	) -> PropertyEditor<U, NoError> {
		return PropertyEditor(self, transform: forward) { proposedInput in
			return .success(reverse(proposedInput))
		}
	}

	// - The failable `map` with parameter `Error`.

	/// Create a mutable mapped view to `self` with a failable setter.
	///
	/// - parameters:
	///   - forward: The value transform to convert `Self.Value` to `U`.
	///   - tryReverse: The failable value transform to convert `U` to
	///                 `Self.Value`.
	///
	/// - returns: A mapping `PropertyEditor`.
	public func map<U, Error: Swift.Error>(
		forward: @escaping (Value) -> U,
		tryReverse: @escaping (U) -> Result<Value, Error>
	) -> PropertyEditor<U, Error> {
		return PropertyEditor<U, Error>(self, transform: forward) { proposedInput in
			return tryReverse(proposedInput)
		}
	}

	// - The default `validate` with parameter `Error`.

	/// Create a mutable view to `self` that validates any proposed value.
	///
	/// - parameters:
	///   - predicate: The closure that validates any proposed value to the
	///                property.
	///
	/// - returns: A validating `PropertyEditor`.
	public func validate<Error: Swift.Error>(
		_ predicate: @escaping (Value) -> Error?
	) -> PropertyEditor<Value, Error> {
		return PropertyEditor(self, transform: { $0 }) { proposedInput in
			return predicate(proposedInput)
				.map { .failure($0) } ?? .success(proposedInput)
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
	/// - returns: A validating `PropertyEditor`.
	public func validate<P: PropertyProtocol, Error: Swift.Error>(
		with other: P,
		_ predicate: @escaping (Value, P.Value) -> Error?
	) -> PropertyEditor<Value, Error> {
		return PropertyEditor<Value, Error>
			.validate({ PropertyEditor(self, transform: { $0 }, $0) }, with: other, predicate)
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
	/// - returns: A validating `PropertyEditor`.
	public func validate<P: _PropertyEditorProtocol, Error: Swift.Error>(
		with other: P,
		_ predicate: @escaping (Value, P.Value) -> Error?
	) -> PropertyEditor<Value, Error> {
		return PropertyEditor<Value, Error>
			.validate({ PropertyEditor(self, transform: { $0 }, $0) }, with: other, predicate)
	}
}

extension _PropertyEditorProtocol {
	fileprivate static func validate<Other: PropertyProtocol, E: Swift.Error>(
		_ initializer: (@escaping (Value) -> Result<Value, E>) -> PropertyEditor<Value, E>,
		with other: Other,
		_ validator: @escaping (Value, Other.Value) -> E?
	) -> PropertyEditor<Value, E> {
		let other = Property(other)

		let property = initializer { proposedInput -> Result<Value, E> in
			return validator(proposedInput, other.value)
				.map { .failure($0) } ?? .success(proposedInput)
		}

		let d = other.signal.observeValues { [weak property] _ in
			if let property = property {
				if case let .failure(failedValue, _) = property.result.value {
					property.property.try(failedValue)
				} else {
					property.property.revalidate()
				}
			}
		}

		property.lifetime.ended.observeCompleted { d?.dispose() }

		return property
	}

	fileprivate static func validate<Other: _PropertyEditorProtocol, E: Swift.Error>(
		_ initializer: (@escaping (Value) -> Result<Value, E>) -> PropertyEditor<Value, E>,
		with other: Other,
		_ validator: @escaping (Value, Other.Value) -> E?
	) -> PropertyEditor<Value, E> {
		let otherValidations = other.property.result

		let property = initializer { proposedInput -> Result<Value, E> in
			let otherValue: Other.Value

			switch otherValidations.value {
			case let .success(value):
				otherValue = value
			case let .failure(value, _):
				otherValue = value
			}

			return validator(proposedInput, otherValue)
				.map { .failure($0) } ?? .success(proposedInput)
		}

		let d = otherValidations.signal.observeValues { [weak property] _ in
			if let property = property {
				if case let .failure(failedValue, _) = property.result.value {
					property.property.try(failedValue)
				} else {
					property.property.revalidate()
				}
			}
		}

		property.lifetime.ended.observeCompleted { d?.dispose() }

		return property
	}
}

extension _PropertyEditorProtocol {
	// - The overriding `map` that invokes the `PropertyEditor`
	//   specialization of `PropertyEditor.init`.

	/// Create a mutable mapped view to `self`.
	///
	/// - parameters:
	///   - forward: The value transform to convert `Self.Value` to `U`.
	///   - reverse: The value transform to convert `U` to `Self.Value`.
	///
	/// - returns: A mapping `PropertyEditor`.
	public func map<U>(
		forward: @escaping (Value) -> U,
		reverse: @escaping (U) -> Value
	) -> PropertyEditor<U, ValidationError> {
		return PropertyEditor(self, transform: forward, errorTransform: { $0 }) { proposedInput in
			return .success(reverse(proposedInput))
		}
	}

	// - The overriding failable `map` that invokes the `PropertyEditor`
	//   specialization of `PropertyEditor.init`.
	/// Create a mutable mapped view to `self` with a failable setter.
	///
	/// - parameters:
	///   - forward: The value transform to convert `Self.Value` to `U`.
	///   - tryReverse: The failable value transform to convert `U` to
	///                 `Self.Value`.
	///
	/// - returns: A mapping `PropertyEditor`.
	public func map<U>(
		forward: @escaping (Value) -> U,
		tryReverse: @escaping (U) -> Result<Value, ValidationError>
	) -> PropertyEditor<U, ValidationError> {
		return PropertyEditor(self, transform: forward, errorTransform: { $0 }) { proposedInput in
			return tryReverse(proposedInput)
		}
	}

	// - The overriding `validate` that invokes the `PropertyEditor`
	//   specialization of `PropertyEditor.init`.

	/// Create a mutable view to `self` that validates any proposed value.
	///
	/// - parameters:
	///   - predicate: The closure that validates any proposed value to the
	///                property.
	///
	/// - returns: A validating `PropertyEditor`.
	public func validate(
		_ predicate: @escaping (Value) -> ValidationError?
	) -> PropertyEditor<Value, ValidationError> {
		return PropertyEditor(self, transform: { $0 }, errorTransform: { $0 }) { proposedInput in
			return predicate(proposedInput)
				.map { .failure($0) } ?? .success(proposedInput)
		}
	}

	// - The overriding `validate(with:)` that invokes the `PropertyEditor`
	//   specialization of `PropertyEditor.init`.

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
	/// - returns: A validating `PropertyEditor`.
	public func validate<P: PropertyProtocol>(
		with other: P,
		_ predicate: @escaping (Value, P.Value) -> ValidationError?
	) -> PropertyEditor<Value, ValidationError> {
		return PropertyEditor<Value, ValidationError>
			.validate({ PropertyEditor(self, transform: { $0 }, errorTransform: { $0 }, $0) },
			          with: other,
			          predicate)
	}

	// - The overriding `validate(with:)` that invokes the `PropertyEditor`
	//   specialization of `PropertyEditor.init`.

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
	/// - returns: A validating `PropertyEditor`.
	public func validate<P: _PropertyEditorProtocol>(
		with other: P,
		_ predicate: @escaping (Value, P.Value) -> ValidationError?
	) -> PropertyEditor<Value, ValidationError> {
		return PropertyEditor<Value, ValidationError>
			.validate({ PropertyEditor(self, transform: { $0 }, errorTransform: { $0 }, $0) },
			          with: other,
			          predicate)
	}
}

extension _PropertyEditorProtocol where ValidationError == NoError {
	// - The overriding failable `map` that invokes the `PropertyEditor`
	//   specialization of `PropertyEditor.init`.
	/// Create a mutable mapped view to `self` with a failable setter.
	///
	/// - parameters:
	///   - forward: The value transform to convert `Self.Value` to `U`.
	///   - tryReverse: The failable value transform to convert `U` to
	///                 `Self.Value`.
	///
	/// - returns: A mapping `PropertyEditor`.
	public func map<U, NewError: Swift.Error>(
		forward: @escaping (Value) -> U,
		tryReverse: @escaping (U) -> Result<Value, NewError>
	) -> PropertyEditor<U, NewError> {
		return PropertyEditor(self, transform: forward) { proposedInput in
			return tryReverse(proposedInput)
		}
	}

	// - The overriding `validate` that invokes the `PropertyEditor`
	//   specialization of `PropertyEditor.init`.

	/// Create a mutable view to `self` that validates any proposed value.
	///
	/// - parameters:
	///   - predicate: The closure that validates any proposed value to the
	///                property.
	///
	/// - returns: A validating `PropertyEditor`.
	public func validate<NewError: Swift.Error>(
		_ predicate: @escaping (Value) -> NewError?
	) -> PropertyEditor<Value, NewError> {
		return PropertyEditor(self, transform: { $0 }) { proposedInput in
			return predicate(proposedInput)
				.map { .failure($0) } ?? .success(proposedInput)
		}
	}

	// - The overriding `validate(with:)` that invokes the `PropertyEditor`
	//   specialization of `PropertyEditor.init`.

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
	/// - returns: A validating `PropertyEditor`.
	public func validate<P: PropertyProtocol, NewError: Swift.Error>(
		with other: P,
		_ predicate: @escaping (Value, P.Value) -> NewError?
	) -> PropertyEditor<Value, NewError> {
		return PropertyEditor<Value, NewError>
			.validate({ PropertyEditor(self, transform: { $0 }, $0) },
			          with: other,
			          predicate)
	}

	// - The overriding `validate(with:)` that invokes the `PropertyEditor`
	//   specialization of `PropertyEditor.init`.

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
	/// - returns: A validating `PropertyEditor`.
	public func validate<P: _PropertyEditorProtocol, NewError: Swift.Error>(
		with other: P,
		_ predicate: @escaping (Value, P.Value) -> NewError?
	) -> PropertyEditor<Value, NewError> {
		return PropertyEditor<Value, NewError>
			.validate({ PropertyEditor(self, transform: { $0 }, $0) },
			          with: other,
			          predicate)
	}
}
