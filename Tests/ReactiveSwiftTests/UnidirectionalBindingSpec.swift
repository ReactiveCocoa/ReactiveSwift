import Dispatch

import Result
import Nimble
import Quick
@testable import ReactiveSwift

class UnidirectionalBindingSpec: QuickSpec {
	override func spec() {
		describe("BindingTarget") {
			var token: Lifetime.Token!
			var lifetime: Lifetime!
			var target: BindingTarget<Int>!
			var optionalTarget: BindingTarget<Int?>!
			var value: Int?

			beforeEach {
				token = Lifetime.Token()
				lifetime = Lifetime(token)
				target = BindingTarget(lifetime: lifetime, setter: { value = $0 })
				optionalTarget = BindingTarget(lifetime: lifetime, setter: { value = $0 })
				value = nil
			}

			describe("non-optional target") {
				it("should pass through the lifetime") {
					expect(target.lifetime).to(beIdenticalTo(lifetime))
				}

				it("should stay bound after deallocation") {
					weak var weakTarget = target

					let property = MutableProperty(1)
					target <~ property
					expect(value) == 1

					target = nil

					property.value = 2
					expect(value) == 2
					expect(weakTarget).to(beNil())
				}

				it("should trigger the supplied setter") {
					expect(value).to(beNil())

					target.consume(1)
					expect(value) == 1
				}

				it("should accept bindings from properties") {
					expect(value).to(beNil())

					let property = MutableProperty(1)
					target <~ property
					expect(value) == 1

					property.value = 2
					expect(value) == 2
				}
			}

			describe("optional target") {
				it("should pass through the lifetime") {
					expect(optionalTarget.lifetime).to(beIdenticalTo(lifetime))
				}

				it("should stay bound after deallocation") {
					weak var weakTarget = optionalTarget

					let property = MutableProperty(1)
					optionalTarget <~ property
					expect(value) == 1

					optionalTarget = nil

					property.value = 2
					expect(value) == 2
					expect(weakTarget).to(beNil())
				}

				it("should trigger the supplied setter") {
					expect(value).to(beNil())

					optionalTarget.consume(1)
					expect(value) == 1
				}

				it("should accept bindings from properties") {
					expect(value).to(beNil())

					let property = MutableProperty(1)
					optionalTarget <~ property
					expect(value) == 1

					property.value = 2
					expect(value) == 2
				}
			}

			it("should not deadlock on the same queue") {
				target = BindingTarget(on: UIScheduler(),
				                       lifetime: lifetime,
				                       setter: { value = $0 })

				let property = MutableProperty(1)
				target <~ property
				expect(value) == 1
			}

			it("should not deadlock on the main thread even if the context was switched to a different queue") {
				let queue = DispatchQueue(label: #file)

				target = BindingTarget(on: UIScheduler(),
				                       lifetime: lifetime,
				                       setter: { value = $0 })

				let property = MutableProperty(1)

				queue.sync {
					_ = target <~ property
				}

				expect(value).toEventually(equal(1))
			}

			it("should not deadlock even if the value is originated from the same queue indirectly") {
				let key = DispatchSpecificKey<Void>()
				DispatchQueue.main.setSpecific(key: key, value: ())

				let mainQueueCounter = Atomic(0)

				let setter: (Int) -> Void = {
					value = $0
					mainQueueCounter.modify { $0 += DispatchQueue.getSpecific(key: key) != nil ? 1 : 0 }
				}

				target = BindingTarget(on: UIScheduler(),
				                       lifetime: lifetime,
				                       setter: setter)

				let scheduler: QueueScheduler
				if #available(OSX 10.10, *) {
					scheduler = QueueScheduler()
				} else {
					scheduler = QueueScheduler(queue: DispatchQueue(label: "com.reactivecocoa.ReactiveSwift.UnidirectionalBindingSpec"))
				}

				let property = MutableProperty(1)
				target <~ property.producer
					.start(on: scheduler)
					.observe(on: scheduler)

				expect(value).toEventually(equal(1))
				expect(mainQueueCounter.value).toEventually(equal(1))

				property.value = 2
				expect(value).toEventually(equal(2))
				expect(mainQueueCounter.value).toEventually(equal(2))
			}
		}
	}
}
