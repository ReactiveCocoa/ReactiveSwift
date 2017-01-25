import Quick
import Nimble
import ReactiveSwift
import Result

class ValidatingPropertySpec: QuickSpec {
	override func spec() {
		describe("MutableValidatingProperty") {
			describe("no dependency") {
				var root: MutableProperty<Int>!
				var validated: MutableValidatingProperty<Int, TestError>!
				var validationResult: FlattenedResult<Int>?

				beforeEach {
					root = MutableProperty(0)
					validated = MutableValidatingProperty(root) { $0 >= 0 ? ($0 == 100 ? .substitution(Int.max, .default) : .success) : .failure(.default) }

					validated.result.signal.observeValues { validationResult = FlattenedResult($0) }

					expect(validated.value) == 0
					expect(FlattenedResult(validated.result.value)) == FlattenedResult.success(0)
					expect(validationResult).to(beNil())
				}

				afterEach {
					validationResult = nil

					weak var weakRoot = root
					expect(weakRoot).notTo(beNil())

					root = nil
					expect(weakRoot).notTo(beNil())

					validated = nil
					expect(weakRoot).to(beNil())

				}

				it("should let valid values get through") {
					validated.value = 10

					expect(validated.value) == 10
					expect(validationResult) == .success(10)
				}

				it("should denote the substitution") {
					validated.value = 100

					expect(validated.value) == Int.max
					expect(validationResult) == .substitution(Int.max, 100, .default)
				}

				it("should block invalid values") {
					validated.value = -10

					expect(validated.value) == 0
					expect(validationResult) == .errorDefault(-10)
				}

				it("should validate changes originated from the root property") {
					root.value = 10

					expect(validated.value) == 10
					expect(validationResult) == .success(10)

					root.value = -10

					expect(validated.value) == -10
					expect(validationResult) == .errorDefault(-10)
				}
			}

			describe("a MutablePropertyProtocol dependency") {
				var other: MutableProperty<String>!
				var validated: MutableValidatingProperty<Int, TestError>!
				var validationResult: FlattenedResult<Int>?

				beforeEach {
					other = MutableProperty("")

					validated = MutableValidatingProperty(0, with: other) { $0 >= 0 && $1 == "🎃" ? ($0 == 100 ? .substitution(Int.max, .default) : .success) : .failure(.default) }

					validated.result.signal.observeValues { validationResult = FlattenedResult($0) }

					expect(validated.value) == 0
					expect(FlattenedResult(validated.result.value)) == FlattenedResult.errorDefault(0)
					expect(validationResult).to(beNil())
				}

				afterEach {
					weak var weakOther = other
					expect(weakOther).toNot(beNil())

					other = nil
					expect(weakOther).to(beNil())

					validationResult = nil
				}

				it("should let valid values get through") {
					other.value = "🎃"

					validated.value = 10

					expect(validated.value) == 10
					expect(validationResult) == .success(10)
				}

				it("should block invalid values") {
					validated.value = -10

					expect(validated.value) == 0
					expect(validationResult) == .errorDefault(-10)
				}

				it("should denote the substitution") {
					other.value = "🎃"
					validated.value = 100

					expect(validated.value) == Int.max
					expect(validationResult) == .substitution(Int.max, 100, .default)
				}

				it("should automatically revalidate the latest failed value if the dependency changes") {
					validated.value = 10

					expect(validated.value) == 0
					expect(validationResult) == .errorDefault(10)

					other.value = "🎃"

					expect(validated.value) == 10
					expect(validationResult) == .success(10)
				}

				it("should automatically revalidate the latest substituted value if the dependency changes") {
					validated.value = 100

					expect(validated.value) == 0
					expect(validationResult) == .errorDefault(100)

					other.value = "🎃"

					expect(validated.value) == Int.max
					expect(validationResult) == .substitution(Int.max, 100, .default)

					validated.value = -1

					expect(validated.value) == Int.max
					expect(validationResult) == .errorDefault(-1)
				}
			}

			describe("a MutableValidatingProperty dependency") {
				var other: MutableValidatingProperty<String, TestError>!
				var validated: MutableValidatingProperty<Int, TestError>!
				var validationResult: FlattenedResult<Int>?

				beforeEach {
					other = MutableValidatingProperty("") { $0.hasSuffix("🎃") && $0 != "🎃" ? .success : .failure(.error2) }

					validated = MutableValidatingProperty(0, with: other) { $0 >= 0 && $1.hasSuffix("🎃") ? ($0 == 100 ? .substitution(Int.max, .default) : .success) : .failure(.default) }

					validated.result.signal.observeValues { validationResult = FlattenedResult($0) }

					expect(validated.value) == 0
					expect(FlattenedResult(validated.result.value)) == FlattenedResult.errorDefault(0)
					expect(validationResult).to(beNil())
				}

				afterEach {
					weak var weakOther = other
					expect(weakOther).toNot(beNil())

					other = nil
					expect(weakOther).to(beNil())

					validationResult = nil
				}

				it("should let valid values get through even if the dependency fails its validation") {
					other.value = "🎃"

					validated.value = 10

					expect(validated.value) == 10
					expect(validationResult) == .success(10)
				}

				it("should block invalid values") {
					validated.value = -10

					expect(validated.value) == 0
					expect(validationResult) == .errorDefault(-10)
				}

				it("should denote the substitution") {
					other.value = "🎃"
					validated.value = 100

					expect(validated.value) == Int.max
					expect(validationResult) == .substitution(Int.max, 100, .default)
				}

				it("should automatically revalidate the latest failed value if the dependency changes") {
					validated.value = 10

					expect(validated.value) == 0
					expect(validationResult) == .errorDefault(10)

					other.value = "🎃"

					expect(validated.value) == 10
					expect(validationResult) == .success(10)
				}

				it("should automatically revalidate the latest substituted value if the dependency changes") {
					validated.value = 100

					expect(validated.value) == 0
					expect(validationResult) == .errorDefault(100)

					other.value = "🎃"

					expect(validated.value) == Int.max
					expect(validationResult) == .substitution(Int.max, 100, .default)

					validated.value = -1

					expect(validated.value) == Int.max
					expect(validationResult) == .errorDefault(-1)
				}

				it("should automatically revalidate the latest failed value whenever the dependency has been proposed a new input") {
					validated.value = 10

					expect(validated.value) == 0
					expect(validationResult) == .errorDefault(10)

					other.value = "🎃"

					expect(other.value) == ""
					expect(FlattenedResult(other.result.value)) == FlattenedResult.error2("🎃")

					expect(validated.value) == 10
					expect(validationResult) == .success(10)

					other.value = "👻🎃"

					expect(other.value) == "👻🎃"
					expect(FlattenedResult(other.result.value)) == FlattenedResult.success("👻🎃")

					expect(validated.value) == 10
					expect(validationResult) == .success(10)
				}
			}
		}
	}
}

private enum FlattenedResult<Value: Equatable>: Equatable {
	case errorDefault(Value)
	case error1(Value)
	case error2(Value)
	case success(Value)
	case substitution(Value, Value, TestError?)

	init(_ result: ValidationResult<Value, TestError>) {
		switch result {
		case let .success(value):
			self = .success(value)

		case let .substitution(substitutedValue, proposedValue, error):
			self = .substitution(substitutedValue, proposedValue, error)

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
		case (let .substitution(lhsSubstitution, lhsProposed, lhsError), let .substitution(rhsSubstitution, rhsProposed, rhsError)):
			return lhsSubstitution == rhsSubstitution && lhsProposed == rhsProposed && lhsError == rhsError
		default:
			return false
		}
	}
}
