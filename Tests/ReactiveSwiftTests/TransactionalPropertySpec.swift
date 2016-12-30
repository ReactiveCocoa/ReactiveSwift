import Quick
import Nimble
import ReactiveSwift
import Result

class TransactionalPropertySpec: QuickSpec {
	override func spec() {
		describe("map(forward:backward:)") {
			var root: MutableProperty<Int>!
			var mapped: TransactionalProperty<String, NoError>!

			beforeEach {
				root = MutableProperty(0)
				mapped = root.map(forward: { "\($0)" }, backward: { Int($0)! })

				expect(mapped.value) == "0"
			}

			afterEach {
				weak var weakRoot = root
				expect(weakRoot).toNot(beNil())

				root = nil
				expect(weakRoot).toNot(beNil())

				mapped = nil
				expect(weakRoot).to(beNil())
			}

			it("should map changes originated from the inner property") {
				root.value = 1
				expect(mapped.value) == "1"
			}

			it("should map changes originated from the outer property") {
				mapped.value = "2"
				expect(root.value) == 2
			}

			it("should propagate the changes") {
				var rootValues: [Int] = []
				var mappedValues: [String] = []

				root.producer.startWithValues { rootValues.append($0) }
				mapped.producer.startWithValues { mappedValues.append($0) }

				root.value = 1

				expect(rootValues) == [0, 1]
				expect(mappedValues) == ["0", "1"]

				mapped.value = "2"

				expect(rootValues) == [0, 1, 2]
				expect(mappedValues) == ["0", "1", "2"]
			}

			describe("nesting") {
				var nestedMapped: TransactionalProperty<Int, NoError>!

				var rootValues: [Int] = []
				var mappedValues: [String] = []
				var nestedMappedValues: [Int] = []

				beforeEach {
					nestedMapped = mapped.map(forward: { Int($0)! }, backward: { "\($0)" })

					root.producer.startWithValues { rootValues.append($0) }
					mapped.producer.startWithValues { mappedValues.append($0) }
					nestedMapped.producer.startWithValues { nestedMappedValues.append($0) }
				}

				afterEach {
					nestedMapped = nil
					rootValues = []
					mappedValues = []
					nestedMappedValues = []
				}

				it("should propagate changes originated from the root") {
					root.value = 1

					expect(rootValues) == [0, 1]
					expect(mappedValues) == ["0", "1"]
					expect(nestedMappedValues) == [0, 1]
				}

				it("should propagate writes to the root") {
					mapped.value = "2"

					expect(rootValues) == [0, 2]
					expect(mappedValues) == ["0", "2"]
					expect(nestedMappedValues) == [0, 2]

					nestedMapped.value = 3

					expect(rootValues) == [0, 2, 3]
					expect(mappedValues) == ["0", "2", "3"]
					expect(nestedMappedValues) == [0, 2, 3]
				}
			}
		}

		describe("map(forward:attemptBackward:)") {
			var root: MutableProperty<Int>!
			var mapped: TransactionalProperty<String, TestError>!
			var validationResult: FlattenedResult!

			beforeEach {
				root = MutableProperty(0)
				mapped = root.map(forward: { "\($0)" }, attemptBackward: { input -> Result<Int, TestError> in
					let integer = Int(input)
					return Result(integer, failWith: TestError.default)
				})
				mapped.validations.producer.startWithValues { validationResult = FlattenedResult($0) }

				expect(mapped.value) == "0"
				expect(validationResult) == .uninitialized
			}

			afterEach {
				weak var weakRoot = root
				expect(weakRoot).toNot(beNil())

				root = nil
				expect(weakRoot).toNot(beNil())

				mapped = nil
				expect(weakRoot).to(beNil())
			}

			it("should map the changes originated from the inner property") {
				root.value = 1

				expect(mapped.value) == "1"
				expect(validationResult) == .uninitialized
			}

			it("should map the valid changes originated from the outer property") {
				mapped.value = "2"

				expect(mapped.value) == "2"
				expect(root.value) == 2
				expect(validationResult) == .success
			}

			it("should block invalid changes originated from the outer property") {
				mapped.value = "😦"

				expect(mapped.value) == "0"
				expect(root.value) == 0
				expect(validationResult) == .errorDefault
			}

			it("should propagate the changes") {
				var rootValues: [Int] = []
				var mappedValues: [String] = []
				var mappedValidations: [FlattenedResult] = []

				root.producer.startWithValues { rootValues.append($0) }
				mapped.producer.startWithValues { mappedValues.append($0) }
				mapped.validations.signal.observeValues { result in
					mappedValidations.append(FlattenedResult(result))
				}

				root.value = 1

				expect(rootValues) == [0, 1]
				expect(mappedValues) == ["0", "1"]
				expect(mappedValidations) == []

				mapped.value = "2"

				expect(rootValues) == [0, 1, 2]
				expect(mappedValues) == ["0", "1", "2"]
				expect(mappedValidations) == [.success]

				mapped.value = "😦"

				expect(rootValues) == [0, 1, 2]
				expect(mappedValues) == ["0", "1", "2"]
				expect(mappedValidations) == [.success, .errorDefault]
			}

			describe("nesting") {
				var nestedMapped: TransactionalProperty<String, TestError>!

				var rootValues: [Int] = []
				var mappedValues: [String] = []
				var mappedValidations: [FlattenedResult] = []
				var nestedMappedValues: [String] = []
				var nestedMappedValidations: [FlattenedResult] = []

				beforeEach {
					// Int <-> String <-> String
					nestedMapped = mapped.map(forward: { "@\($0)" }, attemptBackward: { input -> Result<String, TestError> in
						if let range = input.range(of: "@") {
							return .success(input.substring(with: range.upperBound ..< input.endIndex))
						} else {
							return .failure(TestError.error1)
						}
					})

					root.producer.startWithValues { rootValues.append($0) }
					mapped.producer.startWithValues { mappedValues.append($0) }
					nestedMapped.producer.startWithValues { nestedMappedValues.append($0) }

					mapped.validations.signal.observeValues { result in
						mappedValidations.append(FlattenedResult(result))
					}

					nestedMapped.validations.signal.observeValues { result in
						nestedMappedValidations.append(FlattenedResult(result))
					}
				}

				afterEach {
					nestedMapped = nil

					rootValues = []
					mappedValues = []
					mappedValidations = []
					nestedMappedValues = []
					nestedMappedValidations = []
				}

				it("should propagate changes originated from the root") {
					root.value = 1

					expect(rootValues) == [0, 1]
					expect(mappedValues) == ["0", "1"]
					expect(nestedMappedValues) == ["@0", "@1"]
					expect(mappedValidations) == []
					expect(nestedMappedValidations) == []
				}

				it("should let valid values get through") {
					mapped.value = "2"

					expect(rootValues) == [0, 2]
					expect(mappedValues) == ["0", "2"]
					expect(nestedMappedValues) == ["@0", "@2"]
					expect(mappedValidations) == [.success]
					expect(nestedMappedValidations) == [.success]

					nestedMapped.value = "@3"

					expect(rootValues) == [0, 2, 3]
					expect(mappedValues) == ["0", "2", "3"]
					expect(nestedMappedValues) == ["@0", "@2", "@3"]
					expect(mappedValidations) == [.success, .success]
					expect(nestedMappedValidations) == [.success, .success]
				}

				it("should propagate the validation error back to the outer property in the middle of the chain") {
					nestedMapped.value = "@🚦"

					expect(rootValues) == [0]
					expect(mappedValues) == ["0"]
					expect(nestedMappedValues) == ["@0"]
					expect(mappedValidations) == [.errorDefault]
					expect(nestedMappedValidations) == [.errorDefault]
				}

				it("should block the validation error from proceeding") {
					nestedMapped.value = "🚦"

					expect(rootValues) == [0]
					expect(mappedValues) == ["0"]
					expect(nestedMappedValues) == ["@0"]
					expect(mappedValidations) == []
					expect(nestedMappedValidations) == [.error1]
				}
			}
		}

		describe("validate(_:)") {
			var root: MutableProperty<Int>!
			var validated: TransactionalProperty<Int, TestError>!
			var validationResult: FlattenedResult!

			beforeEach {
				root = MutableProperty(0)
				validated = root.validate { input -> Result<(), TestError> in
					return Result(input >= 0 ? () : nil, failWith: TestError.default)
				}
				validated.validations.producer.startWithValues { validationResult = FlattenedResult($0) }

				expect(validated.value) == root.value
				expect(validationResult) == .uninitialized
			}

			afterEach {
				weak var weakRoot = root
				expect(weakRoot).toNot(beNil())

				root = nil
				expect(weakRoot).toNot(beNil())

				validated = nil
				expect(weakRoot).to(beNil())
			}

			it("should let valid values get through") {
				var isValid = false
				validated.validations.signal.observeValues { isValid = $0?.error == nil }
				expect(isValid) == false

				validated.value = 10
				expect(root.value) == 10
				expect(validated.value) == 10

				expect(isValid) == true
				expect(validationResult) == .success
			}

			it("should block invalid values") {
				var error: TestError? = nil
				validated.validations.signal.observeValues { error = $0?.error }
				expect(error).to(beNil())

				validated.value = -10
				expect(root.value) == 0
				expect(validated.value) == 0

				expect(error) == .default
				expect(validationResult) == .errorDefault
			}

			describe("nesting") {
				var nestedValidated: TransactionalProperty<Int, TestError>!

				var rootValues: [Int] = []
				var validatedValues: [Int] = []
				var validations: [FlattenedResult] = []
				var nestedValidatedValues: [Int] = []
				var nestedValidations: [FlattenedResult] = []

				beforeEach {
					// `validated` blocks negative values. Here we gonna block values in
					// [-99, 99]. So the effective valid range would be [100, inf).
					nestedValidated = validated.validate { input -> Result<(), TestError> in
						return abs(input) >= 100 ? .success(()) : .failure(TestError.error1)
					}

					root.producer.startWithValues { rootValues.append($0) }
					validated.producer.startWithValues { validatedValues.append($0) }
					nestedValidated.producer.startWithValues { nestedValidatedValues.append($0) }

					validated.validations.signal.observeValues { result in
						validations.append(FlattenedResult(result))
					}

					nestedValidated.validations.signal.observeValues { result in
						nestedValidations.append(FlattenedResult(result))
					}

					expect(nestedValidated.value) == 0
				}

				afterEach {
					nestedValidated = nil

					rootValues = []
					validatedValues = []
					validations = []
					nestedValidatedValues = []
					nestedValidations = []
				}

				it("should propagate changes originated from the root") {
					// `1` is invalid in the rules defined by the outer validating
					// properties. But `TransactionalProperty` only validates on the write
					// path, and assumes the root is always right.
					root.value = 1

					expect(validated.value) == 1
					expect(nestedValidated.value) == 1
					expect(validatedValues) == [0, 1]
					expect(nestedValidatedValues) == [0, 1]
				}

				it("should let valid values get through") {
					validated.value = 100

					expect(rootValues) == [0, 100]
					expect(validatedValues) == [0, 100]
					expect(nestedValidatedValues) == [0, 100]
					expect(validations) == [.success]
					expect(nestedValidations) == [.success]

					nestedValidated.value = 200

					expect(rootValues) == [0, 100, 200]
					expect(validatedValues) == [0, 100, 200]
					expect(nestedValidatedValues) == [0, 100, 200]
					expect(validations) == [.success, .success]
					expect(nestedValidations) == [.success, .success]
				}

				it("should block the validation error from proceeding") {
					nestedValidated.value = -50

					expect(rootValues) == [0]
					expect(validatedValues) == [0]
					expect(nestedValidatedValues) == [0]
					expect(validations) == []
					expect(nestedValidations) == [.error1]
				}

				it("should propagate the validation error back to the outer property in the middle of the chain") {
					validated.value = -100

					expect(rootValues) == [0]
					expect(validatedValues) == [0]
					expect(nestedValidatedValues) == [0]
					expect(validations) == [.errorDefault]
					expect(nestedValidations) == [.errorDefault]
				}
			}
		}

		describe("validate(with:_:)") {
			var other: MutableProperty<String>!
			var root: MutableProperty<Int>!
			var validated: TransactionalProperty<Int, TestError>!
			var validationResult: FlattenedResult!

			beforeEach {
				other = MutableProperty("")
				root = MutableProperty(0)
				validated = root.validate(with: other) { input, otherInput -> Result<(), TestError> in
					return Result(input >= 0 && otherInput == "🎃" ? () : nil, failWith: TestError.default)
				}
				validated.validations.producer.startWithValues { validationResult = FlattenedResult($0) }

				expect(validated.value) == root.value
				expect(validationResult) == .uninitialized
			}

			afterEach {
				weak var weakRoot = root
				weak var weakOther = other
				expect(weakRoot).toNot(beNil())
				expect(weakOther).toNot(beNil())

				root = nil
				other = nil
				expect(weakRoot).toNot(beNil())
				expect(weakOther).to(beNil())

				validated = nil
				expect(weakRoot).to(beNil())
			}

			it("should let valid values get through") {
				var isValid = false
				validated.validations.signal.observeValues { isValid = FlattenedResult($0) == .success }
				expect(isValid) == false

				other.value = "🎃"

				validated.value = 10
				expect(root.value) == 10
				expect(validated.value) == 10

				expect(isValid) == true
				expect(validationResult) == .success
			}

			it("should block invalid values") {
				validated.value = -10
				expect(root.value) == 0
				expect(validated.value) == 0

				expect(validationResult) == .errorDefault
			}

			it("should automatically revalidate the latest failed value if the dependency changes") {
				var isValid = false
				validated.validations.signal.observeValues { isValid = FlattenedResult($0) == .success }
				expect(isValid) == false

				validated.value = 10
				expect(root.value) == 0
				expect(validated.value) == 0

				expect(isValid) == false
				expect(validationResult) == .errorDefault

				other.value = "🎃"

				expect(root.value) == 10
				expect(validated.value) == 10
				expect(isValid) == true
				expect(validationResult) == .success
			}

			describe("nesting") {
				var nestedOther: MutableProperty<String>!
				var nestedValidated: TransactionalProperty<Int, TestError>!

				var rootValues: [Int] = []
				var validatedValues: [Int] = []
				var validations: [FlattenedResult] = []
				var nestedValidatedValues: [Int] = []
				var nestedValidations: [FlattenedResult] = []

				beforeEach {
					nestedOther = MutableProperty("")

					// `validated` blocks negative values. Here we gonna block values in
					// [-99, 99]. So the effective valid range would be [100, inf).
					nestedValidated = validated.validate(with: nestedOther) { input, otherInput -> Result<(), TestError> in
						return abs(input) >= 100 && otherInput == "🙈" ? .success(()) : .failure(TestError.error1)
					}

					root.producer.startWithValues { rootValues.append($0) }
					validated.producer.startWithValues { validatedValues.append($0) }
					nestedValidated.producer.startWithValues { nestedValidatedValues.append($0) }

					validated.validations.signal.observeValues { result in
						validations.append(FlattenedResult(result))
					}

					nestedValidated.validations.signal.observeValues { result in
						nestedValidations.append(FlattenedResult(result))
					}

					expect(nestedValidated.value) == 0
				}

				afterEach {
					nestedValidated = nil

					rootValues = []
					validatedValues = []
					validations = []
					nestedValidatedValues = []
					nestedValidations = []
				}

				it("should propagate changes originated from the root") {
					// `1` is invalid in the rules defined by the outer validating
					// properties. But `TransactionalProperty` only validates on the write
					// path, and assumes the root is always right.
					root.value = 1

					expect(validated.value) == 1
					expect(nestedValidated.value) == 1
					expect(validatedValues) == [0, 1]
					expect(nestedValidatedValues) == [0, 1]
				}

				it("should let valid values get through") {
					other.value = "🎃"
					validated.value = 100

					expect(rootValues) == [0, 0, 100]
					expect(validatedValues) == [0, 0, 100]
					expect(nestedValidatedValues) == [0, 0, 100]
					expect(validations) == [.success, .success]
					expect(nestedValidations) == [.success, .success]

					nestedOther.value = "🙈"
					nestedValidated.value = 200

					expect(rootValues) == [0, 0, 100, 100, 200]
					expect(validatedValues) == [0, 0, 100, 100, 200]
					expect(nestedValidatedValues) == [0, 0, 100, 100, 200]
					expect(validations) == [.success, .success, .success, .success]
					expect(nestedValidations) == [.success, .success, .success, .success]
				}

				it("should block the validation error from proceeding") {
					nestedValidated.value = -50

					expect(rootValues) == [0]
					expect(validatedValues) == [0]
					expect(nestedValidatedValues) == [0]
					expect(validations) == []
					expect(nestedValidations) == [.error1]
				}

				it("should propagate the validation error back to the outer property in the middle of the chain") {
					validated.value = -100

					expect(rootValues) == [0]
					expect(validatedValues) == [0]
					expect(nestedValidatedValues) == [0]
					expect(validations) == [.errorDefault]
					expect(nestedValidations) == [.errorDefault]
				}

				it("should propagate the validation error back to the outer property in the middle of the chain") {
					nestedOther.value = "🙈"
					nestedValidated.value = -100

					expect(rootValues) == [0]
					expect(validatedValues) == [0]
					expect(nestedValidatedValues) == [0]
					expect(validations) == [.errorDefault]
					expect(nestedValidations) == [.error1, .errorDefault]
				}
			}
		}
	}
}

private enum FlattenedResult: Int {
	case errorDefault
	case error1
	case error2
	case success
	case uninitialized

	init(_ result: Result<(), TestError>?) {
		switch result {
		case .none:
			self = .uninitialized

		case .success?:
			self = .success

		case let .failure(error)?:
			switch error {
			case .default:
				self = .errorDefault
			case .error1:
				self = .error1
			case .error2:
				self = .error2
			}
		}
	}
}
