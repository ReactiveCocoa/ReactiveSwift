import Quick
import Nimble
import ReactiveSwift
import Result

class PropertyEditorSpec: QuickSpec {
	override func spec() {
		describe("validate(_:)") {
			var root: MutableProperty<Int>!
			var validated: PropertyEditor<Int, TestError>!
			var validationResult: FlattenedResult<Int>?

			beforeEach {
				root = MutableProperty(0)
				validated = root.validate { input -> TestError? in
					return input >= 0 ? nil : .default
				}
				validated.result.signal.observeValues { validationResult = FlattenedResult($0) }

				expect(validated.committed.value) == root.value
				expect(FlattenedResult(validated.result.value)) == FlattenedResult.success(0)
				expect(validationResult).to(beNil())
			}

			afterEach {
				weak var weakRoot = root
				expect(weakRoot).toNot(beNil())

				root = nil
				expect(weakRoot).toNot(beNil())

				validated = nil
				expect(weakRoot).to(beNil())

				validationResult = nil
			}

			it("should let valid values get through") {
				let result = validated.attemptSet(10)

				expect(result) == true
				expect(root.value) == 10
				expect(validated.committed.value) == 10

				expect(validationResult) == .success(10)
			}

			it("should block invalid values") {
				let result = validated.attemptSet(-10)

				expect(result) == false
				expect(root.value) == 0
				expect(validated.committed.value) == 0

				expect(validationResult) == .errorDefault(-10)
			}

			it("should validates values originated from the root") {
				root.value = -10
				expect(validated.committed.value) == -10
				expect(validationResult) == .errorDefault(-10)
			}

			describe("nesting") {
				var nestedValidated: PropertyEditor<Int, TestError>!

				var rootValues: [Int] = []
				var validatedValues: [Int] = []
				var validations: [FlattenedResult<Int>] = []
				var nestedValidatedValues: [Int] = []
				var nestedValidations: [FlattenedResult<Int>] = []

				beforeEach {
					// `validated` blocks negative values. Here we gonna block values in
					// [-99, 99]. So the effective valid range would be [100, inf).
					nestedValidated = validated.validate { input -> TestError? in
						return abs(input) >= 100 ? nil : .error1
					}

					root.signal.observeValues { rootValues.append($0) }
					validated.committed.signal.observeValues { validatedValues.append($0) }
					nestedValidated.committed.signal.observeValues { nestedValidatedValues.append($0) }

					validated.result.signal.observeValues { result in
						validations.append(FlattenedResult(result))
					}

					nestedValidated.result.signal.observeValues { result in
						nestedValidations.append(FlattenedResult(result))
					}

					expect(validated.committed.value) == 0
					expect(nestedValidated.committed.value) == 0
					expect(validatedValues) == []
					expect(nestedValidatedValues) == []
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
					root.value = 1

					expect(validated.committed.value) == 1
					expect(nestedValidated.committed.value) == 1

					expect(validatedValues) == [1]
					expect(nestedValidatedValues) == [1]

					expect(validations) == [.success(1)]
					expect(nestedValidations) == [.error1(1)]

					root.value = -1

					expect(validated.committed.value) == -1
					expect(nestedValidated.committed.value) == -1

					expect(validatedValues) == [1, -1]
					expect(nestedValidatedValues) == [1, -1]

					expect(validations) == [.success(1), .errorDefault(-1)]
					expect(nestedValidations) == [.error1(1), .errorDefault(-1)]

					root.value = 101

					expect(validated.committed.value) == 101
					expect(nestedValidated.committed.value) == 101

					expect(validatedValues) == [1, -1, 101]
					expect(nestedValidatedValues) == [1, -1, 101]

					expect(validations) == [.success(1), .errorDefault(-1), .success(101)]
					expect(nestedValidations) == [.error1(1), .errorDefault(-1), .success(101)]
				}

				it("should let valid values get through") {
					let result = validated.attemptSet(100)

					expect(result) == true
					expect(rootValues) == [100]
					expect(validatedValues) == [100]
					expect(nestedValidatedValues) == [100]
					expect(validations) == [.success(100)]
					expect(nestedValidations) == [.success(100)]

					let result2 = nestedValidated.attemptSet(200)

					expect(result2) == true
					expect(rootValues) == [100, 200]
					expect(validatedValues) == [100, 200]
					expect(nestedValidatedValues) == [100, 200]
					expect(validations) == [.success(100), .success(200)]
					expect(nestedValidations) == [.success(100), .success(200)]
				}

				it("should block the validation error from proceeding") {
					let result = nestedValidated.attemptSet(-50)

					expect(result) == false
					expect(rootValues) == []
					expect(validatedValues) == []
					expect(nestedValidatedValues) == []
					expect(validations) == []
					expect(nestedValidations) == [.error1(-50)]
				}

				it("should propagate the validation error back to the outer property in the middle of the chain") {
					let result = validated.attemptSet(-100)

					expect(result) == false
					expect(rootValues) == []
					expect(validatedValues) == []
					expect(nestedValidatedValues) == []
					expect(validations) == [.errorDefault(-100)]
					expect(nestedValidations) == [.errorDefault(-100)]
				}
			}
		}

		describe("validate(with:_:)") {
			describe("a MutablePropertyProtocol dependency") {
				var other: MutableProperty<String>!
				var root: MutableProperty<Int>!
				var validated: PropertyEditor<Int, TestError>!
				var validationResult: FlattenedResult<Int>?

				beforeEach {
					other = MutableProperty("")
					root = MutableProperty(0)
					validated = root.validate(with: other) { input, otherInput -> TestError? in
						return input >= 0 && otherInput == "🎃" ? nil : .default
					}
					validated.result.signal.observeValues { validationResult = FlattenedResult($0) }

					expect(validated.committed.value) == root.value
					expect(FlattenedResult(validated.result.value)) == FlattenedResult.errorDefault(0)
					expect(validationResult).to(beNil())
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

					validationResult = nil
				}

				it("should let valid values get through") {
					other.value = "🎃"

					let result = validated.attemptSet(10)

					expect(result) == true
					expect(root.value) == 10
					expect(validated.committed.value) == 10

					expect(validationResult) == .success(10)
				}

				it("should block invalid values") {
					let result = validated.attemptSet(-10)

					expect(result) == false
					expect(root.value) == 0
					expect(validated.committed.value) == 0

					expect(validationResult) == .errorDefault(-10)
				}

				it("should validates values originated from the root") {
					root.value = -10
					expect(validated.committed.value) == -10
					expect(validationResult) == .errorDefault(-10)
				}

				it("should automatically revalidate the latest failed value if the dependency changes") {
					let result = validated.attemptSet(10)

					expect(result) == false
					expect(root.value) == 0
					expect(validated.committed.value) == 0

					expect(validationResult) == .errorDefault(10)

					other.value = "🎃"

					expect(root.value) == 10
					expect(validated.committed.value) == 10
					expect(validationResult) == .success(10)
				}

				describe("nesting") {
					var nestedOther: MutableProperty<String>!
					var nestedValidated: PropertyEditor<Int, TestError>!

					var rootValues: [Int] = []
					var validatedValues: [Int] = []
					var validations: [FlattenedResult<Int>] = []
					var nestedValidatedValues: [Int] = []
					var nestedValidations: [FlattenedResult<Int>] = []

					beforeEach {
						nestedOther = MutableProperty("")

						// `validated` blocks negative values. Here we gonna block values in
						// [-99, 99]. So the effective valid range would be [100, inf).
						nestedValidated = validated.validate(with: nestedOther) { input, otherInput -> TestError? in
							return abs(input) >= 100 && otherInput == "🙈" ? nil : .error1
						}

						root.signal.observeValues { rootValues.append($0) }
						validated.committed.signal.observeValues { validatedValues.append($0) }
						nestedValidated.committed.signal.observeValues { nestedValidatedValues.append($0) }

						validated.result.signal.observeValues { result in
							validations.append(FlattenedResult(result))
						}

						nestedValidated.result.signal.observeValues { result in
							nestedValidations.append(FlattenedResult(result))
						}

						expect(nestedValidated.committed.value) == 0
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
						root.value = 1

						expect(validated.committed.value) == 1
						expect(nestedValidated.committed.value) == 1

						expect(validatedValues) == [1]
						expect(nestedValidatedValues) == [1]

						expect(validations) == [.errorDefault(1)]
						expect(nestedValidations) == [.errorDefault(1)]
					}

					it("should let valid values get through") {
						other.value = "🎃"

						expect(rootValues) == [0]
						expect(validatedValues) == [0]
						expect(nestedValidatedValues) == [0]
						expect(validations) == [.success(0)]
						expect(nestedValidations) == [.error1(0)]

						let result = validated.attemptSet(70)

						expect(result) == true
						expect(rootValues) == [0, 70]
						expect(validatedValues) == [0, 70]
						expect(nestedValidatedValues) == [0, 70]
						expect(validations) == [.success(0), .success(70)]
						expect(nestedValidations) == [.error1(0), .error1(70)]

						nestedOther.value = "🙈"

						expect(rootValues) == [0, 70]
						expect(validatedValues) == [0, 70]
						expect(nestedValidatedValues) == [0, 70]
						expect(validations) == [.success(0), .success(70)]
						expect(nestedValidations) == [.error1(0), .error1(70), .error1(70)]

						let result2 = nestedValidated.attemptSet(200)

						expect(result2) == true
						expect(rootValues) == [0, 70, 200]
						expect(validatedValues) == [0, 70, 200]
						expect(nestedValidatedValues) == [0, 70, 200]
						expect(validations) == [.success(0), .success(70), .success(200)]
						expect(nestedValidations) == [.error1(0), .error1(70), .error1(70), .success(200)]
					}

					it("should block the validation error from proceeding") {
						let result = nestedValidated.attemptSet(-50)

						expect(result) == false
						expect(rootValues) == []
						expect(validatedValues) == []
						expect(nestedValidatedValues) == []
						expect(validations) == []
						expect(nestedValidations) == [.error1(-50)]
					}

					it("should propagate the validation error back to the outer property in the middle of the chain") {
						let result = validated.attemptSet(-100)

						expect(result) == false
						expect(rootValues) == []
						expect(validatedValues) == []
						expect(nestedValidatedValues) == []
						expect(validations) == [.errorDefault(-100)]
						expect(nestedValidations) == [.errorDefault(-100)]
					}

					it("should propagate the validation error back to the outer property in the middle of the chain") {
						nestedOther.value = "🙈"

						expect(rootValues) == []
						expect(validatedValues) == []
						expect(nestedValidatedValues) == []
						expect(validations) == []
						expect(nestedValidations) == [.error1(0)]
						
						let result = nestedValidated.attemptSet(-100)

						expect(result) == false
						expect(rootValues) == []
						expect(validatedValues) == []
						expect(nestedValidatedValues) == []
						expect(validations) == [.errorDefault(-100)]
						expect(nestedValidations) == [.error1(0), .errorDefault(-100)]
					}
				}
			}
		}

		describe("a PropertyEditor dependency") {
			var other: PropertyEditor<String, TestError>!
			var root: MutableProperty<Int>!
			var validated: PropertyEditor<Int, TestError>!
			var validationResult: FlattenedResult<Int>?

			beforeEach {
				other = MutableProperty("").validate { input -> TestError? in
					return input.hasSuffix("🎃") && input != "🎃" ? nil : .error2
				}

				root = MutableProperty(0)
				validated = root.validate(with: other) { input, otherInput -> TestError? in
					return input >= 0 && otherInput.hasSuffix("🎃") ? nil : .default
				}
				validated.result.signal.observeValues { validationResult = FlattenedResult($0) }

				expect(validated.committed.value) == root.value
				expect(FlattenedResult(validated.result.value)) == FlattenedResult.errorDefault(0)
				expect(validationResult).to(beNil())
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

				validationResult = nil
			}

			it("should let valid values get through even if the dependency fails its validation") {
				let otherResult = other.attemptSet("🎃")
				expect(otherResult) == false

				let result = validated.attemptSet(10)
				expect(result) == true

				expect(root.value) == 10
				expect(validated.committed.value) == 10

				expect(validationResult) == .success(10)
			}

			it("should block invalid values") {
				let result = validated.attemptSet(-10)
				expect(result) == false

				expect(root.value) == 0
				expect(validated.committed.value) == 0

				expect(validationResult) == .errorDefault(-10)
			}

			it("should validates values originated from the root") {
				root.value = -10
				expect(validated.committed.value) == -10
				expect(validationResult) == .errorDefault(-10)
			}

			it("should automatically revalidate the latest failed value if the dependency changes") {
				let result = validated.attemptSet(10)
				expect(result) == false

				expect(root.value) == 0
				expect(validated.committed.value) == 0

				expect(validationResult) == .errorDefault(10)

				let otherResult = other.attemptSet("🎃")
				expect(otherResult) == false

				expect(root.value) == 10
				expect(validated.committed.value) == 10
				expect(validationResult) == .success(10)
			}

			it("should automatically revalidate the latest failed value whenever the dependency has been proposed a new input") {
				let result = validated.attemptSet(10)

				expect(result) == false
				expect(root.value) == 0
				expect(validated.committed.value) == 0

				expect(validationResult) == .errorDefault(10)

				let otherResult = other.attemptSet("🎃")

				expect(otherResult) == false
				expect(other.committed.value) == ""
				expect(FlattenedResult(other.result.value)) == FlattenedResult.error2("🎃")

				expect(root.value) == 10
				expect(validated.committed.value) == 10
				expect(validationResult) == .success(10)

				let otherResult2 = other.attemptSet("👻🎃")

				expect(otherResult2) == true
				expect(other.committed.value) == "👻🎃"
				expect(FlattenedResult(other.result.value)) == FlattenedResult.success("👻🎃")

				expect(root.value) == 10
				expect(validated.committed.value) == 10
				expect(validationResult) == .success(10)
			}
		}
	}
}

private enum FlattenedResult<Value: Equatable>: Equatable {
	case errorDefault(Value)
	case error1(Value)
	case error2(Value)
	case success(Value)

	init(_ result: ValidationResult<Value, TestError>) {
		switch result {
		case let .success(value):
			self = .success(value)

		case let .failure(value, error):
			switch error {
			case .default:
				self = .errorDefault(value)
			case .error1:
				self = .error1(value)
			case .error2:
				self = .error2(value)
			}
		}
	}

	static func ==(left: FlattenedResult<Value>, right: FlattenedResult<Value>) -> Bool {
		switch (left, right) {
		case (let .errorDefault(lhsValue), let .errorDefault(rhsValue)):
			return lhsValue == rhsValue
		case (let .error1(lhsValue), let .error1(rhsValue)):
			return lhsValue == rhsValue
		case (let .error2(lhsValue), let .error2(rhsValue)):
			return lhsValue == rhsValue
		case (let .success(lhsValue), let .success(rhsValue)):
			return lhsValue == rhsValue
		default:
			return false
		}
	}
}
