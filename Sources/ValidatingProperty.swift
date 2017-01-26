import Result

/// A mutable property that validates mutations before committing them.
///
/// If the property wraps an arbitrary mutable property, changes originated from
/// the inner property are monitored, and would be automatically validated.
/// Note that these would still appear as committed values even if they fail the
/// validation.
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
	private let getter: () -> Value
	private let setter: (Value) -> Void

	/// The result of the last attempted edit of the root property.
	public let result: Property<ValidationResult<Value, ValidationError>>

	/// The current value of the property.
	///
	/// The value could have failed the validation. Refer to `result` for the
	/// latest validation result.
	public var value: Value {
		get { return getter() }
		set { setter(newValue) }
	}

	/// A producer for Signals that will send the property's current value,
	/// followed by all changes over time, then complete when the property has
	/// deinitialized.
	public let producer: SignalProducer<Value, NoError>

	/// A signal that will send the property's changes over time,
	/// then complete when the property has deinitialized.
	public let signal: Signal<Value, NoError>

	/// The lifetime of the property.
	public let lifetime: Lifetime

	/// Create a `MutableValidatingProperty` that presents a mutable validating
	/// view for an inner mutable property.
	///
	/// The proposed value is only committed when `success` is returned by the
	/// `validator` closure.
	///
	/// - note: `inner` is retained by the created property.
	///
	/// - parameters:
	///   - inner: The inner property which validated values are committed to.
	///   - validator: The closure to invoke for any proposed value to `self`.
	public init<Inner: ComposableMutablePropertyProtocol>(
		_ inner: Inner,
		_ validator: @escaping (Value) -> ValidatorOutput<Value, ValidationError>
	) where Inner.Value == Value {
		getter = { inner.value }
		producer = inner.producer
		signal = inner.signal
		lifetime = inner.lifetime

		// This flag temporarily suspends the monitoring on the inner property for
		// writebacks that are triggered by successful validations.
		var isSettingInnerValue = false

		(result, setter) = inner.withValue { initial in
			let mutableResult = MutableProperty(ValidationResult(initial, validator(initial)))

			mutableResult <~ inner.signal
				.filter { _ in !isSettingInnerValue }
				.map { ValidationResult($0, validator($0)) }

			return (Property(capturing: mutableResult), { input in
				let writebackValue: Value? = mutableResult.modify { result in
					result = ValidationResult(input, validator(input))
					return result.value
				}

				if let value = writebackValue {
					isSettingInnerValue = true
					inner.value = value
					isSettingInnerValue = false
				}
			})
		}
	}

	/// Create a `MutableValidatingProperty` that validates mutations before
	/// committing them.
	///
	/// The proposed value is only committed when `success` is returned by the
	/// `validator` closure.
	///
	/// - parameters:
	///   - initial: The initial value of the property. It is not required to
	///              pass the validation as specified by `validator`.
	///   - validator: The closure to invoke for any proposed value to `self`.
	public convenience init(
		_ initial: Value,
		_ validator: @escaping (Value) -> ValidatorOutput<Value, ValidationError>
	) {
		self.init(MutableProperty(initial), validator)
	}

	/// Create a `MutableValidatingProperty` that presents a mutable validating
	/// view for an inner mutable property.
	///
	/// The proposed value is only committed when `success` is returned by the
	/// `validator` closure.
	///
	/// - note: `inner` is retained by the created property.
	///
	/// - parameters:
	///   - inner: The inner property which validated values are committed to.
	///   - other: The property that `validator` depends on.
	///   - validator: The closure to invoke for any proposed value to `self`.
	public convenience init<Other: PropertyProtocol>(
		_ inner: MutableProperty<Value>,
		with other: Other,
		_ validator: @escaping (Value, Other.Value) -> ValidatorOutput<Value, ValidationError>
	) {
		let other = Property(other)

		self.init(inner) { input in
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

	/// Create a `MutableValidatingProperty` that validates mutations before
	/// committing them.
	///
	/// The proposed value is only committed when `success` is returned by the
	/// `validator` closure.
	///
	/// - parameters:
	///   - initial: The initial value of the property. It is not required to
	///              pass the validation as specified by `validator`.
	///   - other: The property that `validator` depends on.
	///   - validator: The closure to invoke for any proposed value to `self`.
	public convenience init<Other: PropertyProtocol>(
		_ initial: Value,
		with other: Other,
		_ validator: @escaping (Value, Other.Value) -> ValidatorOutput<Value, ValidationError>
	) {
		self.init(MutableProperty(initial), with: other, validator)
	}

	/// Create a `MutableValidatingProperty` that presents a mutable validating
	/// view for an inner mutable property.
	///
	/// The proposed value is only committed when `success` is returned by the
	/// `validator` closure.
	///
	/// - note: `inner` is retained by the created property.
	///
	/// - parameters:
	///   - inner: The inner property which validated values are committed to.
	///   - other: The property that `validator` depends on.
	///   - validator: The closure to invoke for any proposed value to `self`.
	public convenience init<U, E: Swift.Error>(
		_ inner: MutableProperty<Value>,
		with other: MutableValidatingProperty<U, E>,
		_ validator: @escaping (Value, U) -> ValidatorOutput<Value, ValidationError>
	) {
		self.init(inner, with: other, validator)
	}

	/// Create a `MutableValidatingProperty` that validates mutations before
	/// committing them.
	///
	/// The proposed value is only committed when `success` is returned by the
	/// `validator` closure.
	///
	/// - parameters:
	///   - initial: The initial value of the property. It is not required to
	///              pass the validation as specified by `validator`.
	///   - other: The property that `validator` depends on.
	///   - validator: The closure to invoke for any proposed value to `self`.
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
}

/// Represents a decision of a validator of a validating property made on a
/// proposed value.
public enum ValidatorOutput<Value, Error: Swift.Error> {
	/// The value is valid.
	case success

	/// The value is invalid, but the validator can provide a substitution derived
	/// from the invalid value that would be considered valid.
	case substitution(Value, Error?)

	/// The value is invalid.
	case failure(Error)
}

/// Represents the result of the validation performed by a validating property.
public enum ValidationResult<Value, Error: Swift.Error> {
	/// The value passed the validation.
	case success(Value)

	/// The value was a substituted value due to a failed validation.
	case substitution(substituted: Value, proposed: Value, Error?)

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
