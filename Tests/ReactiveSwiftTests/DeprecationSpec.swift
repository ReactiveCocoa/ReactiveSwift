import Quick
import Nimble
import ReactiveSwift
import Result

final class TestTarget: BindingTargetProtocol {
	typealias Value = Int

	var counter = 0

	let (lifetime, token) = Lifetime.make()

	func consume(_ value: Int) {
		counter += 1
	}
}

class DeprecationSpec: QuickSpec {
	override func spec() {
		describe("BindingTargetProtocol") {
			it("should make the conforming type a valid BindingTargetProvider automatically") {
				let target = TestTarget()
				let property = MutableProperty<Int>(0)

				expect(target.counter) == 0

				target <~ property
				expect(target.counter) == 1

				property.value = 0
				expect(target.counter) == 2
			}
		}
	}
}
