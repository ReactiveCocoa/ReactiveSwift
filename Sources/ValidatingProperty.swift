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
public final class MutableValidatingProperty<Value, ValidationError: Swift.Error>: MutablePropertyProtocol {
	private let storage: MutableProperty<Value>

	private let setter: (Value) -> Void

	/// The result of the last attempted edit of the root property.
	public let result: Property<ValidationResult<Value, ValidationError>>

	/// The current value of the property.
	///
	/// The value could have failed the validation. Refer to `result` for the
	/// latest validation result.
	public var value: Value {
		get { return storage.value }
		set { setter(newValue) }
	}

	public var producer: SignalProducer<Value, NoError> {
		return storage.producer
	}

	public var signal: Signal<Value, NoError> {
		return storage.signal
	}

	/// The lifetime of the editor.
	public var lifetime: Lifetime {
		return storage.lifetime
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
	///   - initial: The initial value.
	///   - validator: The closure to invoke for any proposed value to `self`.
	public init(
		_ initial: Value,
		_ validator: @escaping (Value, inout (ValidationError?)) -> Void
	) {
		var mutesValueBackpropagation = false

		storage = MutableProperty(initial)
		let mutableResult = MutableProperty(ValidationResult(initial, validator: validator))
		result = Property(capturing: mutableResult)

		mutableResult <~ storage.signal
			.filter { _ in !mutesValueBackpropagation }
			.map { ValidationResult($0, validator: validator) }

		setter = { [storage] input in
			var error: ValidationError?
			validator(input, &error)

			if let error = error {
				mutableResult.value = .failure(input, error)
			} else {
				mutesValueBackpropagation = true
				storage.value = input
				mutableResult.value = .success(input)
				mutesValueBackpropagation = false
			}
		}
	}

	public convenience init<Other: PropertyProtocol>(
		_ initial: Value,
		with other: Other,
		_ validator: @escaping (Value, Other.Value, inout (ValidationError?)) -> Void
	) {
		let other = Property(other)

		self.init(initial) { input, error in
			validator(input, other.value, &error)
		}

		other.signal
			.take(during: lifetime)
			.observeValues { [weak self] _ in
				if let s = self {
					s.withValue { current in
						if case let .failure(failedValue, _) = s.result.value {
							s.value = failedValue
						} else {
							s.value = current
						}
					}
				}
			}
	}

	public convenience init<U, E: Swift.Error>(
		_ initial: Value,
		with other: MutableValidatingProperty<U, E>,
		_ validator: @escaping (Value, U, inout (ValidationError?)) -> Void
	) {
		let otherValidations = other.result

		self.init(initial) { input, error in
			let otherValue: U

			switch otherValidations.value {
			case let .success(value):
				otherValue = value
			case let .failure(value, _):
				otherValue = value
			}

			validator(input, otherValue, &error)
		}

		otherValidations.signal
			.take(during: lifetime)
			.observeValues { [weak self] _ in
			if let s = self {
				s.withValue { current in
					if case let .failure(failedValue, _) = s.result.value {
						s.value = failedValue
					} else {
						s.value = current
					}
				}
			}
		}
	}

	@discardableResult
	public func withValue<R>(_ action: (Value) throws -> R) rethrows -> R {
		return try storage.withValue(action: action)
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

	fileprivate init(_ value: Value, validator: (Value, inout (Error?)) -> Void) {
		var error: Error?
		validator(value, &error)

		self = error.map { .failure(value, $0) } ?? .success(value)
	}
}
