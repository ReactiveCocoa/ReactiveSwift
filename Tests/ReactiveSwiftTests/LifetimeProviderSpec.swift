import ReactiveSwift
import enum Result.NoError
import Quick
import Nimble

class LifetimeProviderSpec: QuickSpec {
	private final class TestObject: LifetimeProvider {
		let lifetime: Lifetime
		private let token = Lifetime.Token()

		var counter = 0

		init() {
			lifetime = Lifetime(token)
		}

		func unary(a: Int) { counter += 1 }
		func binary(a: Int, b: Int) { counter += 10 }
		func tenary(a: Int, b: Int, c: Int) { counter += 100 }
		func quaternary(a: Int, b: Int, c: Int, d: Int) { counter += 1000 }
		func quinary(a: Int, b: Int, c: Int, d: Int, e: Int) { counter += 10000 }
		func senary(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) { counter += 100000 }
	}

	override func spec() {
		describe("lift") {
			var object: TestObject?
			weak var _object: TestObject?

			beforeEach {
				object = TestObject()
				_object = object
			}

			func testLifting<U>(value: U, expectedCount: Int, transform: @escaping (TestObject) -> (U) -> Void) {
				let lifted = object!.lift(transform)
				let (signal, observer) = Signal<U, NoError>.pipe()

				lifted(signal)
				expect(object!.counter) == 0

				observer.send(value: value)
				expect(object!.counter) == expectedCount
			}

			it("should lift a unary method") {
				testLifting(value: 0,
				            expectedCount: 1,
				            transform: { $0.unary })
			}

			it("should lift a binary method") {
				testLifting(value: (0, 0),
				            expectedCount: 10,
				            transform: { $0.binary })
			}

			it("should lift a tenary method") {
				testLifting(value: (0, 0, 0),
				            expectedCount: 100,
				            transform: { $0.tenary })
			}

			it("should lift a quaternary method") {
				testLifting(value: (0, 0, 0, 0),
				            expectedCount: 1000,
				            transform: { $0.quaternary })
			}

			it("should lift a quinary method") {
				testLifting(value: (0, 0, 0, 0, 0),
				            expectedCount: 10000,
				            transform: { $0.quinary })
			}

			it("should lift a senary method") {
				testLifting(value: (0, 0, 0, 0, 0, 0),
				            expectedCount: 100000,
				            transform: { $0.senary })
			}

			func testRetainCycle<U>(_ transform: @escaping (TestObject) -> (U) -> Void) {
				weak var weakSignal: Signal<U, NoError>?

				autoreleasepool {
					let lifted = object!.lift(transform)
					let (signal, _) = Signal<U, NoError>.pipe()

					lifted(signal)
					weakSignal = signal
				}

				expect(weakSignal).toNot(beNil())

				object = nil
				expect(_object).to(beNil())
				expect(weakSignal).to(beNil())
			}

			it("should not cause a retain cycle with an unary method") {
				testRetainCycle { $0.unary }
			}

			it("should not cause a retain cycle with a binary method") {
				testRetainCycle { $0.binary }
			}

			it("should not cause a retain cycle with a ternary method") {
				testRetainCycle { $0.tenary }
			}

			it("should not cause a retain cycle with a quaternary method") {
				testRetainCycle { $0.quaternary }
			}

			it("should not cause a retain cycle with a quinary method") {
				testRetainCycle { $0.quinary }
			}

			it("should not cause a retain cycle with a senary method") {
				testRetainCycle { $0.senary }
			}
		}
	}
}
