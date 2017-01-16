import Result

/// An editor that monitors, validates and commits changes to its root property.
///
/// Validation failure raised by intermediate editors would back-propagate to
/// the outer editors.
///
/// ```
/// let outer = root
///   .validate { $0 == "Valid" ? nil : .intermediateInvalid }
///   .validate { $0.hasSuffix("Valid") ? nil : .outerInvalid }
///
/// outer.attemptSet("isValid")
///
/// intermediate.result.value // `.failure("isValid", .intermediateInvalid)`
/// outer.result.value        // `.failure("isValid", .intermediateInvalid)`
/// ```
///
/// Changes originated from the intermediate editors and the root property are
/// monitored and would trigger validations automatically.
///
/// ```
/// let root = MutableProperty("Valid")
/// let outer = root
///   .validate { $0 == "Valid" ? nil : .outerInvalid }
///
/// outer.result.value        // `.success("Valid")
///
/// root.value = "🎃"
/// outer.result.value        // `.failure("🎃", .outerInvalid)`
/// ```
public final class PropertyEditor<Value, ValidationError: Error> {
	/// The committed value of the editor, synchronized with the root property.
	///
	/// As changes can be initiated from the intermediate editors and the root
	/// property without being first validated by `self`, the committed value can
	/// be invalid.
	///
	/// Refer to `result` for the latest validation result.
	public var committed: Property<Value>

	/// The lifetime token of the editor.
	private let lifetimeToken: Lifetime.Token

	/// The lifetime of the editor.
	public let lifetime: Lifetime

	/// The result of the last attempted edit of the root property.
	public let result: Property<ValidationResult<Value, ValidationError>>

	/// The action associated with the editor.
	private let action: (Value) -> Bool

	/// The synchronization mechanic of the root property.
	private let rootLock: RootPropertyLockBoxBase<()>

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
	///   - validator: The closure to invoke for any proposed value to `self`.
	public init<M: ComposableMutablePropertyProtocol>(
		_ inner: M,
		_ validator: @escaping (Value) -> ValidationError?
	) where M.Value == Value {
		var mutesValueBackpropagation = false

		let _validations: MutableProperty<ValidationResult<Value, ValidationError>> = inner.withValue { innerValue in
			let property = MutableProperty(ValidationResult(innerValue, validator: validator))

			property <~ inner.signal
				.filter { _ in !mutesValueBackpropagation }
				.map { ValidationResult($0, validator: validator) }

			return property
		}

		self.result = Property(capturing: _validations)
		self.lifetimeToken = Lifetime.Token()
		self.lifetime = Lifetime(lifetimeToken)
		self.committed = Property(capturing: inner)
		self.rootLock = RootPropertyLockBox(inner)

		action = { input in
			if let error = validator(input) {
				_validations.value = .failure(input, error)
				return false
			} else {
				mutesValueBackpropagation = true
				inner.value = input
				_validations.value = .success(input)
				mutesValueBackpropagation = false
				return true
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
	///   - errorTransform: The error transform for the presentation.
	///   - body: The closure to invoke for any proposed value to `self`.
	public convenience init<T: _PropertyEditorProtocol>(
		_ inner: T,
		errorTransform: @escaping (T.ValidationError) -> ValidationError,
		_ body: @escaping (Value) -> ValidationError?
	) where T.Value == Value {
		self.init(inner, validator: body, validationSetup: { validations in
			validations <~ inner.property.result.signal
				.map { $0.map(errorTransform, validator: body) }
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
	///   - body: The closure to invoke for any proposed value to `self`.
	public convenience init<T: _PropertyEditorProtocol>(
		_ inner: T,
		_ body: @escaping (Value) -> ValidationError?
	) where T.Value == Value, T.ValidationError == NoError {
		self.init(inner, validator: body, validationSetup: nil)
	}

	private init<T: _PropertyEditorProtocol>(
		_ inner: T,
		validator: @escaping (Value) -> ValidationError?,
		validationSetup: ((MutableProperty<ValidationResult<Value, ValidationError>>) -> Void)?
	) where T.Value == Value {
		let _validations: MutableProperty<ValidationResult<Value, ValidationError>> = inner.property.rootLock.lock {
			let property = MutableProperty(ValidationResult(inner.property.committed.value, validator: validator))
			validationSetup?(property)
			return property
		}

		self.result = Property(capturing: _validations)
		self.lifetimeToken = Lifetime.Token()
		self.lifetime = Lifetime(lifetimeToken)
		self.committed = inner.property.committed
		self.rootLock = inner.property.rootLock


		action = { input in
			if let error = validator(input) {
				_validations.value = .failure(input, error)
				return false
			} else {
				return inner.property.action(input)
			}
		}
	}

	/// Attempt to edit the property with the given value.
	///
	/// - parameters:
	///   - newValue: The proposed value.
	///
	/// - returns: A boolean indicating whether the attempt succeds.
	@discardableResult
	public func attemptSet(_ newValue: Value) -> Bool {
		return rootLock.lock {
			return action(newValue)
		}
	}

	/// Atomically performs an arbitrary action using the current value of the
	/// variable.
	///
	/// - parameters:
	///   - action: A closure that accepts current property value.
	///
	/// - returns: The result of the action.
	public func withValue<Result>(action: (Value) throws -> Result) rethrows -> Result {
		return try rootLock.lock {
			return try action(committed.value)
		}
	}

	internal func revalidate() {
		rootLock.lock {
			_ = action(committed.value)
		}
	}
}

extension PropertyEditor: BindingTargetProtocol {
	public func consume(_ value: Value) {
		self.attemptSet(value)
	}
}

extension PropertyEditor: BindingSourceProtocol {
	public func observe(_ observer: Observer<Value, NoError>, during lifetime: Lifetime) -> Disposable? {
		return committed.producer
			.take(during: lifetime)
			.start(observer)
	}
}

// FIXME: To be replaced by extensions with concrete same-type requirement in
//        Swift 3.1.
public protocol _PropertyEditorProtocol: class {
	associatedtype Value
	associatedtype ValidationError: Swift.Error

	var property: PropertyEditor<Value, ValidationError> { get }

	init<T: _PropertyEditorProtocol>(
		_ inner: T,
		errorTransform: @escaping (T.ValidationError) -> ValidationError,
		_ body: @escaping (Value) -> ValidationError?
	) where T.Value == Value

	init<T: _PropertyEditorProtocol>(
		_ inner: T,
		_ body: @escaping (Value) -> ValidationError?
	) where T.Value == Value, T.ValidationError == NoError
}

extension PropertyEditor: _PropertyEditorProtocol {
	public var property: PropertyEditor<Value, ValidationError> {
		return self
	}
}

/// Represents the result of the validation performed by `PropertyEditor`.
public enum ValidationResult<Value, Error: Swift.Error> {
	/// The value passed the validation.
	case success(Value)

	/// The value failed the validation.
	case failure(Value, Error)

	/// Whether the validation was failed.
	public var isFailure: Bool {
		if case .failure = self {
			return true
		} else {
			return false
		}
	}

	/// Extract the error if the validation was failed.
	public var error: Error? {
		if case let .failure(_, error) = self {
			return error
		} else {
			return nil
		}
	}

	/// Convert `self` to `Result`, ignoring the failed value.
	public var result: Result<Value, Error> {
		switch self {
		case let .success(value):
			return .success(value)
		case let .failure(_, error):
			return .failure(error)
		}
	}

	fileprivate init(_ value: Value, validator: (Value) -> Error?) {
		switch validator(value) {
		case .none:
			self = .success(value)
		case let .some(error):
			self = .failure(value, error)
		}
	}

	fileprivate func map<E: Swift.Error>(_ errorTransform: (Error) -> E, validator: (Value) -> E?) -> ValidationResult<Value, E> {
		switch self {
		case let .success(value):
			switch validator(value) {
			case .none:
				return .success(value)

			case let .some(error):
				return .failure(value, error)
			}

		case let .failure(value, error):
			return .failure(value, errorTransform(error))
		}
	}
}

// FIXME: The `()` type parameter of `RootPropertyLockBoxBase` was introduced to
//        workaround an issue preventing `lock` being overriden.
private class RootPropertyLockBox<Property: ComposableMutablePropertyProtocol>: RootPropertyLockBoxBase<()> {
	private let base: Property

	init(_ base: Property) { self.base = base }

	override func lock<R>(_ action: () throws -> R) rethrows -> R {
		return try base.withValue { _ in return try action() }
	}
}

private class RootPropertyLockBoxBase<U> {
	func lock<R>(_ action: (U) throws -> R) rethrows -> R {
		fatalError()
	}
}

extension ComposableMutablePropertyProtocol {
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
		return PropertyEditor(self, predicate)
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
			.validate({ PropertyEditor(self, $0) }, with: other, predicate)
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
			.validate({ PropertyEditor(self, $0) }, with: other, predicate)
	}
}

extension _PropertyEditorProtocol {
	fileprivate static func validate<Other: PropertyProtocol, E: Swift.Error>(
		_ initializer: (@escaping (Value) -> E?) -> PropertyEditor<Value, E>,
		with other: Other,
		_ validator: @escaping (Value, Other.Value) -> E?
	) -> PropertyEditor<Value, E> {
		let other = Property(other)

		let property = initializer { validator($0, other.value) }

		let d = other.signal.observeValues { [weak property] _ in
			if let property = property {
				if case let .failure(failedValue, _) = property.result.value {
					property.property.attemptSet(failedValue)
				} else {
					property.property.revalidate()
				}
			}
		}

		property.lifetime.ended.observeCompleted { d?.dispose() }

		return property
	}

	fileprivate static func validate<Other: _PropertyEditorProtocol, E: Swift.Error>(
		_ initializer: (@escaping (Value) -> E?) -> PropertyEditor<Value, E>,
		with other: Other,
		_ validator: @escaping (Value, Other.Value) -> E?
	) -> PropertyEditor<Value, E> {
		let otherValidations = other.property.result

		let property = initializer { proposedInput -> E? in
			let otherValue: Other.Value

			switch otherValidations.value {
			case let .success(value):
				otherValue = value
			case let .failure(value, _):
				otherValue = value
			}

			return validator(proposedInput, otherValue)
		}

		let d = otherValidations.signal.observeValues { [weak property] _ in
			if let property = property {
				if case let .failure(failedValue, _) = property.result.value {
					property.property.attemptSet(failedValue)
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
		return PropertyEditor(self, errorTransform: { $0 }, predicate)
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
			.validate({ PropertyEditor(self, errorTransform: { $0 }, $0) }, with: other, predicate)
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
			.validate({ PropertyEditor(self, errorTransform: { $0 }, $0) }, with: other, predicate)
	}
}

extension _PropertyEditorProtocol where ValidationError == NoError {
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
		return PropertyEditor(self, predicate)
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
			.validate({ PropertyEditor(self, $0) }, with: other, predicate)
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
			.validate({ PropertyEditor(self, $0) }, with: other, predicate)
	}
}
