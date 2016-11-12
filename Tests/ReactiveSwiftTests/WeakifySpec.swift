import ReactiveSwift
import Quick
import Nimble

class WeakifySpec: QuickSpec {
	private class TestObject {
		func unary(a: Int) {}
		func binary(a: Int, b: Int) {}
		func tenary(a: Int, b: Int, c: Int) {}
		func quaternary(a: Int, b: Int, c: Int, d: Int) {}
		func quinary(a: Int, b: Int, c: Int, d: Int, e: Int) {}
		func senary(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) {}
	}

	override func spec() {
		describe("weakify") {
			var object: TestObject?
			weak var _object: TestObject?
			var action: (() -> Void)!

			beforeEach {
				object = TestObject()
				_object = object
			}

			afterEach {
				action()
			}

			it("should weakify a unary closure") {
				let weakified = weakify(object!, { $0.unary })
				action = { weakified(1) }
				object = nil
				expect(_object).to(beNil())
			}

			it("should weakify a binary closure") {
				let weakified = weakify(object!, { $0.binary })
				action = { weakified(1, 2) }
				object = nil
				expect(_object).to(beNil())
			}

			it("should weakify a tenary closure") {
				let weakified = weakify(object!, { $0.tenary })
				action = { weakified(1, 2, 3) }
				object = nil
				expect(_object).to(beNil())
			}

			it("should weakify a quaternary closure") {
				let weakified =  weakify(object!, { $0.quaternary })
				action = { weakified(1, 2, 3, 4) }
				object = nil
				expect(_object).to(beNil())
			}

			it("should weakify a quinary closure") {
				let weakified = weakify(object!, { $0.quinary })
				action = { weakified(1, 2, 3, 4, 5) }
				object = nil
				expect(_object).to(beNil())
			}

			it("should weakify a senary closure") {
				let weakified = weakify(object!, { $0.senary })
				action = { weakified(1, 2, 3, 4, 5, 6) }
				object = nil
				expect(_object).to(beNil())
			}
		}
	}
}
