//
//  ActionSpec.swift
//  ReactiveSwift
//
//  Created by Justin Spahr-Summers on 2014-12-11.
//  Copyright (c) 2014 GitHub. All rights reserved.
//

import Foundation
import Dispatch
import Result
import Nimble
import Quick
import ReactiveSwift

class ActionSpec: QuickSpec {
	override func spec() {
		describe("Action") {
			var action: Action<Int, String, NSError>!
			var enabled: MutableProperty<Bool>!

			var executionCount = 0
			var completedCount = 0
			var values: [String] = []
			var errors: [NSError] = []

			var scheduler: TestScheduler!
			let testError = NSError(domain: "ActionSpec", code: 1, userInfo: nil)

			beforeEach {
				executionCount = 0
				completedCount = 0
				values = []
				errors = []
				enabled = MutableProperty(false)

				scheduler = TestScheduler()
				action = Action(enabledIf: enabled) { number in
					return SignalProducer { observer, disposable in
						executionCount += 1

						if number % 2 == 0 {
							observer.send(value: "\(number)")
							observer.send(value: "\(number)\(number)")

							scheduler.schedule {
								observer.sendCompleted()
							}
						} else {
							scheduler.schedule {
								observer.send(error: testError)
							}
						}
					}
				}

				action.values.observeValues { values.append($0) }
				action.errors.observeValues { errors.append($0) }
				action.completed.observeValues { completedCount += 1 }
			}

			it("should retain the state property") {
				var property: MutableProperty<Bool>? = MutableProperty(false)
				weak var weakProperty = property
				
				var action: Action<(), (), NoError>? = Action(state: property!, enabledIf: { _ in true }) { _ in
					return .empty
				}
				
				expect(weakProperty).toNot(beNil())
				
				property = nil
				expect(weakProperty).toNot(beNil())
				
				action = nil
				expect(weakProperty).to(beNil())
				
				// Mute "unused variable" warning.
				_ = action
			}

			it("should be disabled and not executing after initialization") {
				expect(action.isEnabled.value) == false
				expect(action.isExecuting.value) == false
			}

			it("should error if executed while disabled") {
				var receivedError: ActionError<NSError>?
				var disabledErrorsTriggered = false

				action.disabledErrors.observeValues {
					disabledErrorsTriggered = true
				}

				action.apply(0).startWithFailed {
					receivedError = $0
				}

				expect(receivedError).notTo(beNil())
				expect(disabledErrorsTriggered) == true
				if let error = receivedError {
					let expectedError = ActionError<NSError>.disabled
					expect(error == expectedError) == true
				}
			}

			it("should enable and disable based on the given property") {
				enabled.value = true
				expect(action.isEnabled.value) == true
				expect(action.isExecuting.value) == false

				enabled.value = false
				expect(action.isEnabled.value) == false
				expect(action.isExecuting.value) == false
			}

			it("should not deadlock") {
				final class ViewModel {
					let action2 = Action<(), (), NoError> { SignalProducer(value: ()) }
				}

				let action1 = Action<(), ViewModel, NoError> { SignalProducer(value: ViewModel()) }

				// Fixed in #267. (https://github.com/ReactiveCocoa/ReactiveSwift/pull/267)
				//
				// The deadlock happened as the observer disposable releases the closure
				// `{ _ in viewModel }` here without releasing the mapped signal's
				// `updateLock` first. The deinitialization of the closure triggered the
				// propagation of terminal event of the `Action`, which eventually hit
				// the mapped signal and attempted to acquire `updateLock` to transition
				// the signal's state.
				action1.values
					.flatMap(.latest) { viewModel in viewModel.action2.values.map { _ in viewModel } }
					.observeValues { _ in }

				action1.apply().start()
				action1.apply().start()
			}

			if #available(macOS 10.10, *) {
				it("should not loop indefinitely") {
					let condition = MutableProperty(1)

					let action = Action<Void, Void, NoError>(state: condition, enabledIf: { $0 == 0 }) { _ in
						return .empty
					}

					let disposable = CompositeDisposable()

					waitUntil(timeout: 0.01) { done in
						let target = DispatchQueue(label: "test target queue")
						let highPriority = QueueScheduler(qos: .userInitiated, targeting: target)
						let lowPriority = QueueScheduler(qos: .default, targeting: target)

						disposable += action.isExecuting.producer
							.observe(on: highPriority)
							.startWithValues { _ in
								condition.value = 10
							}

						disposable += lowPriority.schedule {
							done()
						}
					}

					disposable.dispose()
				}
			}

			describe("completed") {
				beforeEach {
					enabled.value = true
				}

				it("should send a value whenever the producer completes") {
					action.apply(0).start()
					expect(completedCount) == 0

					scheduler.run()
					expect(completedCount) == 1

					action.apply(2).start()
					scheduler.run()
					expect(completedCount) == 2
				}

				it("should not send a value when the producer fails") {
					action.apply(1).start()
					scheduler.run()
					expect(completedCount) == 0
				}

				it("should not send a value when the producer is interrupted") {
					let disposable = action.apply(0).start()
					disposable.dispose()
					scheduler.run()
					expect(completedCount) == 0
				}

				it("should not send a value when the action is disabled") {
					enabled.value = false
					action.apply(0).start()
					scheduler.run()
					expect(completedCount) == 0
				}
			}

			describe("execution") {
				beforeEach {
					enabled.value = true
				}

				it("should execute successfully") {
					var receivedValue: String?

					action.apply(0)
						.assumeNoErrors()
						.startWithValues {
							receivedValue = $0
						}

					expect(executionCount) == 1
					expect(action.isExecuting.value) == true
					expect(action.isEnabled.value) == false

					expect(receivedValue) == "00"
					expect(values) == [ "0", "00" ]
					expect(errors) == []

					scheduler.run()
					expect(action.isExecuting.value) == false
					expect(action.isEnabled.value) == true

					expect(values) == [ "0", "00" ]
					expect(errors) == []
				}

				it("should execute with an error") {
					var receivedError: ActionError<NSError>?

					action.apply(1).startWithFailed {
						receivedError = $0
					}

					expect(executionCount) == 1
					expect(action.isExecuting.value) == true
					expect(action.isEnabled.value) == false

					scheduler.run()
					expect(action.isExecuting.value) == false
					expect(action.isEnabled.value) == true

					expect(receivedError).notTo(beNil())
					if let error = receivedError {
						let expectedError = ActionError<NSError>.producerFailed(testError)
						expect(error == expectedError) == true
					}

					expect(values) == []
					expect(errors) == [ testError ]
				}
			}

			describe("bindings") {
				it("should execute successfully") {
					var receivedValue: String?
					let (signal, observer) = Signal<Int, NoError>.pipe()

					action.values.observeValues { receivedValue = $0 }

					action <~ signal

					enabled.value = true

					expect(executionCount) == 0
					expect(action.isExecuting.value) == false
					expect(action.isEnabled.value) == true

					observer.send(value: 0)

					expect(executionCount) == 1
					expect(action.isExecuting.value) == true
					expect(action.isEnabled.value) == false

					expect(receivedValue) == "00"
					expect(values) == [ "0", "00" ]
					expect(errors) == []

					scheduler.run()
					expect(action.isExecuting.value) == false
					expect(action.isEnabled.value) == true

					expect(values) == [ "0", "00" ]
					expect(errors) == []
				}
			}
		}

		describe("using a property as input") {
			let echo: (Int) -> SignalProducer<Int, NoError> = SignalProducer.init(value:)

			it("executes the action with the property's current value") {
				let input = MutableProperty(0)
				let action = Action(state: input, execute: echo)

				var values: [Int] = []
				action.values.observeValues { values.append($0) }

				input.value = 1
				action.apply().start()
				input.value = 2
				action.apply().start()
				input.value = 3
				action.apply().start()

				expect(values) == [1, 2, 3]
			}

			it("is disabled if the property is nil") {
				let input = MutableProperty<Int?>(1)
				let action = Action(state: input, execute: echo)

				expect(action.isEnabled.value) == true
				input.value = nil
				expect(action.isEnabled.value) == false
			}
		}

		describe("composing with extra enabled check") {
			var sut: Action<Int, Int, NoError>!
			let enableInner = MutableProperty(true)
			let enableOuter = MutableProperty(true)
			var observer: Signal<Int, NoError>.Observer? = nil
			let inner: Action<Int, Int, NoError> = Action(enabledIf: enableInner, execute: { _ in
				return SignalProducer { obs, _ in observer = obs }
			})

			beforeEach {
				observer = nil
				sut = Action(enabledIf: enableOuter, wrapping: inner)
			}

			it("disables outer based on outer.isEnabled and inner.isEnabled") {
				expect(sut.isEnabled.value) == true
				enableOuter.value = false
				expect(sut.isEnabled.value) == false
				enableOuter.value = true
				expect(sut.isEnabled.value) == true
				enableInner.value = false
				expect(sut.isEnabled.value) == false
				enableInner.value = true
				expect(sut.isEnabled.value) == true
			}

			it("updates outer.isEnabled and outer.isExecuting when outer is run") {
				enableInner.value = true
				enableOuter.value = true
				sut.apply(3).start()
				expect(sut.isExecuting.value) == true
				expect(sut.isEnabled.value) == false
				observer?.send(value: 2)
				observer?.sendCompleted()
				expect(sut.isExecuting.value) == false
				expect(sut.isEnabled.value) == true
			}

			it("updates outer.isEnabled and outer.isExecuting when inner is run") {
				enableInner.value = true
				enableOuter.value = true
				inner.apply(3).start()
				expect(sut.isExecuting.value) == true
				expect(sut.isEnabled.value) == false
				observer?.send(value: 2)
				observer?.sendCompleted()
				expect(sut.isExecuting.value) == false
				expect(sut.isEnabled.value) == true
			}
		}
	}
}
