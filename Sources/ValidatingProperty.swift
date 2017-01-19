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
		_ validator: @escaping (Value) -> ValidatorOutput<Value, ValidationError>
	) {
		var mutesValueBackpropagation = false

		storage = MutableProperty(initial)
		let mutableResult = MutableProperty(ValidationResult(initial, validator(initial)))
		result = Property(capturing: mutableResult)

		mutableResult <~ storage.signal
			.filter { _ in !mutesValueBackpropagation }
			.map { ValidationResult($0, validator($0)) }

		setter = { [storage] input in
			let writebackValue: Value? = mutableResult.modify { result in
				result = ValidationResult(input, validator(input))
				return result.value
			}

			if let value = writebackValue {
				mutesValueBackpropagation = true
				storage.value = value
				mutesValueBackpropagation = false
			}
		}
	}

	public convenience init<Other: PropertyProtocol>(
		_ initial: Value,
		with other: Other,
		_ validator: @escaping (Value, Other.Value) -> ValidatorOutput<Value, ValidationError>
	) {
		let other = Property(other)

		self.init(initial) { input in
			return validator(input, other.value)
		}

		other.signal
			.take(during: lifetime)
			.observeValues { [weak self] _ in
				if let s = self {
					switch s.result.value {
					case let .failure(failedValue, _):
						s.value = failedValue
					case let .substitution(substitutedValue, _, _):
						s.value = substitutedValue
					case let .success(value):
						s.value = value
					}
				}
			}
	}

	public convenience init<U, E: Swift.Error>(
		_ initial: Value,
		with other: MutableValidatingProperty<U, E>,
		_ validator: @escaping (Value, U) -> ValidatorOutput<Value, ValidationError>
	) {
		let otherValidations = other.result

		self.init(initial) { input in
			let otherValue: U

			switch otherValidations.value {
			case let .success(value):
				otherValue = value
			case let .substitution(_, value, _):
				otherValue = value
			case let .failure(value, _):
				otherValue = value
			}

			return validator(input, otherValue)
		}

		otherValidations.signal
			.take(during: lifetime)
			.observeValues { [weak self] _ in
			if let s = self {
				switch s.result.value {
				case let .failure(failedValue, _):
					s.value = failedValue
				case let .substitution(substitutedValue, _, _):
					s.value = substitutedValue
				case let .success(value):
					s.value = value
				}
			}
		}
	}

	@discardableResult
	public func withValue<R>(_ action: (Value) throws -> R) rethrows -> R {
		return try storage.withValue(action: action)
	}
}

public enum ValidatorOutput<Value, Error: Swift.Error> {
	case success

	case substitution(Value, Error)

	case failure(Error)
}

/// Represents the result of the validation performed by `PropertyEditor`.
public enum ValidationResult<Value, Error: Swift.Error> {
	/// The value passed the validation.
	case success(Value)

	/// The value was a substituted value due to a failed validation.
	case substitution(substituted: Value, proposed: Value, Error)

	/// The value failed the validation.
	case failure(proposed: Value, Error)

	/// Whether the validation was failed.
	public var isFailure: Bool {
		if case .failure = self {
			return true
		} else {
			return false
		}
	}

	/// Extract the value if the validation is passed, or a substituted value
	/// for failure is provided.
	public var value: Value? {
		switch self {
		case let .success(value):
			return value
		case let .substitution(value, _, _):
			return value
		case .failure:
			return nil
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

	fileprivate init(_ value: Value, _ output: ValidatorOutput<Value, Error>) {
		switch output {
		case .success:
			self = .success(value)

		case let .substitution(substitutedValue, error):
			self = .substitution(substituted: substitutedValue, proposed: value, error)

		case let .failure(error):
			self = .failure(proposed: value, error)
		}
	}
}
