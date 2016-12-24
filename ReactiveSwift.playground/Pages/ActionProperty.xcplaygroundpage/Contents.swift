import ReactiveSwift
import Result

let root = MutableProperty(0)

// First level.
let A: ActionProperty<Int, ValidationError<Int>> = scope("A") {
	let property = root.validate { input -> Result<(), ValidationError<Int>> in
		print("A's validator is invoked.")

		if (0 ... 5).contains(input) {
			return .success()
		} else {
			return .failure(.invalid(input))
		}
	}

	property.validations.observeValues { validation in
		print("A result: \(validation); value=\(property.value); rootValue=\(root.value)")
	}

	set(property, to: -5)
	set(property, to: 5)

	return property
}

// Second level.
let B: ActionProperty<Int, ValidationError<Int>> = scope("B") {
	let property = A.validate { input -> Result<(), ValidationError<Int>> in
		print("B's validator is invoked.")
		if (0 ... 10).contains(input) || (100 ... 110).contains(input) {
			return .success()
		} else {
			return .failure(.invalid(input))
		}
	}

	property.validations.observeValues { validation in
		print("B result: \(validation); value=\(property.value); rootValue=\(root.value)")
	}

	set(property, to: -5)
	set(property, to: 5)
	set(property, to: 10)
	set(property, to: 100)

	return property
}

// Third level.
let C: ActionProperty<Int, ValidationError<Int>> = scope("C") {
	let property = B.validate { input -> Result<(), ValidationError<Int>> in
		print("C's validator is invoked.")
		if (0 ... 15).contains(input) || (200 ... 210).contains(input) {
			return .success()
		} else {
			return .failure(.invalid(input))
		}
	}

	property.validations.observeValues { validation in
		print("C result: \(validation); value=\(property.value); rootValue=\(root.value)")
	}

	set(property, to: -5)
	set(property, to: 5)
	set(property, to: 15)
	set(property, to: 100)
	set(property, to: 200)

	return property
}

// Fourth level.
let D: ActionProperty<Int, Error2<ValidationError<String>, ValidationError<Int>>> = scope("D") {
	let property = C.validate { input -> Result<(), ValidationError<String>> in
		print("D's validator is invoked.")
		if (0 ... 20).contains(input) || (300 ... 310).contains(input) {
			return .success()
		} else {
			return .failure(.invalid(String(input)))
		}
	}

	property.validations.observeValues { validation in
		print("D result: \(validation); value=\(property.value); rootValue=\(root.value)")
	}

	set(property, to: -5)
	set(property, to: 5)
	set(property, to: 20)
	set(property, to: 100)
	set(property, to: 200)
	set(property, to: 300)

	return property
}

// Fifth level.
let E: ActionProperty<String, Error2<ValidationError<String>, ValidationError<Int>>> = scope("E") {
	let property = D.map(forward: { String("\($0)") },
	                           backward: { Int($0)! })

	property.validations.observeValues { validation in
		print("E result: \(validation); value=\(property.value); rootValue=\(root.value)")
	}

	set(property, to: "-5")
	set(property, to: "5")
	set(property, to: "20")
	set(property, to: "100")
	set(property, to: "200")
	set(property, to: "300")

	return property
}

// Utilities
enum ValidationError<Value>: Error {
	case invalid(Value)
}

var scopeName = "undefined"

func scope<R>(_ name: String, _ body: () -> R) -> R {
	scopeName = name

	print("## [Scope: \(scopeName)] ========================================================\n")

	return body()
}

func set<P: MutablePropertyProtocol>(_ p: P, to value: P.Value) {
	print("Setting \(scopeName) to \(value)")
	p.value = value
	print("")
}