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
/// let outer = MutableValidatingProperty(root) {
///   $0 == "Valid" ? .success : .failure(.outerInvalid)
/// }
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
		// Capture a copy that reflects `other` without influencing the lifetime of
		// `other`.
		let other = Property(other)

		self.init(inner) { input in
			return validator(input, other.value)
		}

		// When `other` pushes out a new value, the resulting property would react 
		// by revalidating itself with its last attempted value, regardless of
		// success or failure.
		other.signal
			.take(during: lifetime)
			.observeValues { [weak self] _ in
				guard let s = self else { return }

				switch s.result.value {
				case let .failure(failedValue, _):
					s.value = failedValue
				case let .substitution(_, failedValue, _):
					s.value = failedValue
				case let .success(value):
					s.value = value
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
		// Capture only `other.result` but not `other`.
		let otherValidations = other.result

		self.init(initial) { input in
			let otherValue: U

			switch otherValidations.value {
			case let .success(succeeded):
				otherValue = succeeded
			case let .substitution(_, proposed, _):
				otherValue = proposed
			case let .failure(failed, _):
				otherValue = failed
			}

			return validator(input, otherValue)
		}

		// When `other` pushes out a new validation result, the resulting property
		// would react by revalidating itself with its last attempted value,
		// regardless of success or failure.
		otherValidations.signal
			.take(during: lifetime)
			.observeValues { [weak self] _ in
				guard let s = self else { return }

				switch s.result.value {
				case let .failure(failed, _):
					s.value = failed
				case let .substitution(_, proposed, _):
					s.value = proposed
				case let .success(succeeded):
					s.value = succeeded
				}
			}
	}
}

/// Represents a decision of a validator of a validating property made on a
/// proposed value.
public enum ValidatorOutput<Value, Error: Swift.Error> {
	/// The value passes the validation.
	case success

	/// The value fails the validation, but the validator provides a
	/// substitution which is considered valid.
	case substitution(Value, Error?)

	/// The value fails the validation.
	case failure(Error)
}

/// Represents the result of the validation performed by a validating property.
public enum ValidationResult<Value, Error: Swift.Error> {
	/// The value passed the validation.
	case success(Value)

	/// The value failed the validation, but the validator provided a
	/// substitution which is considered valid.
	case substitution(substituted: Value, proposed: Value, error: Error?)

	/// The value failed the validation.
	case failure(proposed: Value, error: Error)

	/// Whether the validation was failed.
	public var isFailure: Bool {
		if case .failure = self {
			return true
		} else {
			return false
		}
	}

	/// Extract the valid value.
	///
	/// - note: The `substitution` case is also considered valid.
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

		case let .substitution(substituted, error):
			self = .substitution(substituted: substituted, proposed: value, error: error)

		case let .failure(error):
			self = .failure(proposed: value, error: error)
		}
	}
}
