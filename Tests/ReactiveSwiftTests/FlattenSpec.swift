//
//  FlattenSpec.swift
//  ReactiveSwift
//
//  Created by Oleg Shnitko on 1/22/16.
//  Copyright © 2016 GitHub. All rights reserved.
//

import Result
import Nimble
import Quick
import ReactiveSwift

private extension SignalProtocol {
	typealias Pipe = (signal: Signal<Value, Error>, observer: Observer<Value, Error>)
}

private typealias Pipe = Signal<SignalProducer<Int, TestError>, TestError>.Pipe

class FlattenSpec: QuickSpec {
	override func spec() {
		func describeSignalFlattenDisposal(_ flattenStrategy: FlattenStrategy, name: String) {
			describe(name) {
				var pipe: Pipe!
				var disposable: Disposable?

				beforeEach {
					pipe = Signal.pipe()
					disposable = pipe.signal
						.flatten(flattenStrategy)
						.observe { _ in }
				}

				afterEach {
					disposable?.dispose()
				}

				context("disposal") {
					var disposed = false

					beforeEach {
						disposed = false
						pipe.observer.send(value: SignalProducer<Int, TestError> { _, disposable in
							disposable += ActionDisposable {
								disposed = true
							}
						})
					}

					it("should dispose inner signals when outer signal interrupted") {
						pipe.observer.sendInterrupted()
						expect(disposed) == true
					}

					it("should dispose inner signals when outer signal failed") {
						pipe.observer.send(error: .default)
						expect(disposed) == true
					}

					it("should not dispose inner signals when outer signal completed") {
						pipe.observer.sendCompleted()
						expect(disposed) == false
					}
				}
			}
		}

		context("Signal") {
			describeSignalFlattenDisposal(.latest, name: "switchToLatest")
			describeSignalFlattenDisposal(.merge, name: "merge")
			describeSignalFlattenDisposal(.concat, name: "concat")
		}

		func describeSignalProducerFlattenDisposal(_ flattenStrategy: FlattenStrategy, name: String) {
			describe(name) {
				it("disposes original signal when result signal interrupted") {
					var disposed = false

					let disposable = SignalProducer<SignalProducer<(), NoError>, NoError> { _, disposable in
						disposable += ActionDisposable {
							disposed = true
						}
					}
						.flatten(flattenStrategy)
						.start()

					disposable.dispose()
					expect(disposed) == true
				}
			}
		}

		context("SignalProducer") {
			describeSignalProducerFlattenDisposal(.latest, name: "switchToLatest")
			describeSignalProducerFlattenDisposal(.merge, name: "merge")
			describeSignalProducerFlattenDisposal(.concat, name: "concat")
		}
		
		describe("Signal.flatten()") {
			it("works with TestError and a TestError Signal") {
				typealias Inner = Signal<Int, TestError>
				typealias Outer = Signal<Inner, TestError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatten(.latest)
					.assumeNoErrors()
					.observeValues { value in
						observed = value
					}
				
				outerObserver.send(value: inner)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with NoError and a TestError Signal") {
				typealias Inner = Signal<Int, TestError>
				typealias Outer = Signal<Inner, NoError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatten(.latest)
					.assumeNoErrors()
					.observeValues { value in
						observed = value
					}
				
				outerObserver.send(value: inner)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with NoError and a NoError Signal") {
				typealias Inner = Signal<Int, NoError>
				typealias Outer = Signal<Inner, NoError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatten(.latest)
					.observeValues { value in
						observed = value
					}
				
				outerObserver.send(value: inner)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with TestError and a NoError Signal") {
				typealias Inner = Signal<Int, NoError>
				typealias Outer = Signal<Inner, TestError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatten(.latest)
					.assumeNoErrors()
					.observeValues { value in
						observed = value
					}
				
				outerObserver.send(value: inner)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with TestError and a TestError SignalProducer") {
				typealias Inner = SignalProducer<Int, TestError>
				typealias Outer = Signal<Inner, TestError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatten(.latest)
					.assumeNoErrors()
					.observeValues { value in
						observed = value
					}
				
				outerObserver.send(value: inner)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with NoError and a TestError SignalProducer") {
				typealias Inner = SignalProducer<Int, TestError>
				typealias Outer = Signal<Inner, NoError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatten(.latest)
					.assumeNoErrors()
					.observeValues { value in
						observed = value
					}
				
				outerObserver.send(value: inner)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with NoError and a NoError SignalProducer") {
				typealias Inner = SignalProducer<Int, NoError>
				typealias Outer = Signal<Inner, NoError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatten(.latest)
					.observeValues { value in
						observed = value
					}
				
				outerObserver.send(value: inner)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with TestError and a NoError SignalProducer") {
				typealias Inner = SignalProducer<Int, NoError>
				typealias Outer = Signal<Inner, TestError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatten(.latest)
					.assumeNoErrors()
					.observeValues { value in
						observed = value
					}
				
				outerObserver.send(value: inner)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with SequenceType as a value") {
				let (signal, innerObserver) = Signal<[Int], NoError>.pipe()
				let sequence = [1, 2, 3]
				var observedValues = [Int]()
				
				signal
					.flatten(.concat)
					.observeValues { value in
						observedValues.append(value)
					}
				
				innerObserver.send(value: sequence)
				expect(observedValues) == sequence
			}

			it("works with Property and any arbitrary error") {
				_ = Signal<Property<Int>, TestError>.empty
					.flatten(.latest)
			}

			it("works with Property and NoError") {
				_ = Signal<Property<Int>, NoError>.empty
					.flatten(.latest)
			}
		}
		
		describe("SignalProducer.flatten()") {
			it("works with TestError and a TestError Signal") {
				typealias Inner = Signal<Int, TestError>
				typealias Outer = SignalProducer<Inner, TestError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatten(.latest)
					.assumeNoErrors()
					.startWithValues { value in
						observed = value
					}
				
				outerObserver.send(value: inner)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with NoError and a TestError Signal") {
				typealias Inner = Signal<Int, TestError>
				typealias Outer = SignalProducer<Inner, NoError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatten(.latest)
					.assumeNoErrors()
					.startWithValues { value in
						observed = value
					}
				
				outerObserver.send(value: inner)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with NoError and a NoError Signal") {
				typealias Inner = Signal<Int, NoError>
				typealias Outer = SignalProducer<Inner, NoError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatten(.latest)
					.startWithValues { value in
						observed = value
					}
				
				outerObserver.send(value: inner)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with TestError and a NoError Signal") {
				typealias Inner = Signal<Int, NoError>
				typealias Outer = SignalProducer<Inner, TestError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatten(.latest)
					.assumeNoErrors()
					.startWithValues { value in
						observed = value
					}
				
				outerObserver.send(value: inner)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with TestError and a TestError SignalProducer") {
				typealias Inner = SignalProducer<Int, TestError>
				typealias Outer = SignalProducer<Inner, TestError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatten(.latest)
					.assumeNoErrors()
					.startWithValues { value in
						observed = value
					}
				
				outerObserver.send(value: inner)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with NoError and a TestError SignalProducer") {
				typealias Inner = SignalProducer<Int, TestError>
				typealias Outer = SignalProducer<Inner, NoError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatten(.latest)
					.assumeNoErrors()
					.startWithValues { value in
						observed = value
					}
				
				outerObserver.send(value: inner)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with NoError and a NoError SignalProducer") {
				typealias Inner = SignalProducer<Int, NoError>
				typealias Outer = SignalProducer<Inner, NoError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatten(.latest)
					.startWithValues { value in
						observed = value
					}
				
				outerObserver.send(value: inner)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with TestError and a NoError SignalProducer") {
				typealias Inner = SignalProducer<Int, NoError>
				typealias Outer = SignalProducer<Inner, TestError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatten(.latest)
					.assumeNoErrors()
					.startWithValues { value in
						observed = value
					}
				
				outerObserver.send(value: inner)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with SequenceType as a value") {
				let sequence = [1, 2, 3]
				var observedValues = [Int]()
				
				let producer = SignalProducer<[Int], NoError>(value: sequence)
				producer
					.flatten(.latest)
					.startWithValues { value in
						observedValues.append(value)
					}
				
				expect(observedValues) == sequence
			}

			it("works with Property and any arbitrary error") {
				_ = SignalProducer<Property<Int>, TestError>.empty
					.flatten(.latest)
			}

			it("works with Property and NoError") {
				_ = SignalProducer<Property<Int>, NoError>.empty
					.flatten(.latest)
			}
		}
		
		describe("Signal.flatMap()") {
			it("works with TestError and a TestError Signal") {
				typealias Inner = Signal<Int, TestError>
				typealias Outer = Signal<Int, TestError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatMap(.latest) { _ in inner }
					.assumeNoErrors()
					.observeValues { value in
						observed = value
					}
				
				outerObserver.send(value: 4)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with NoError and a TestError Signal") {
				typealias Inner = Signal<Int, TestError>
				typealias Outer = Signal<Int, NoError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatMap(.latest) { _ in inner }
					.assumeNoErrors()
					.observeValues { value in
						observed = value
					}
				
				outerObserver.send(value: 4)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with NoError and a NoError Signal") {
				typealias Inner = Signal<Int, NoError>
				typealias Outer = Signal<Int, NoError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatMap(.latest) { _ in inner }
					.observeValues { value in
						observed = value
					}
				
				outerObserver.send(value: 4)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with TestError and a NoError Signal") {
				typealias Inner = Signal<Int, NoError>
				typealias Outer = Signal<Int, TestError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatMap(.latest) { _ in inner }
					.assumeNoErrors()
					.observeValues { value in
						observed = value
					}
				
				outerObserver.send(value: 4)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with TestError and a TestError SignalProducer") {
				typealias Inner = SignalProducer<Int, TestError>
				typealias Outer = Signal<Int, TestError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatMap(.latest) { _ in inner }
					.assumeNoErrors()
					.observeValues { value in
						observed = value
					}
				
				outerObserver.send(value: 4)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with NoError and a TestError SignalProducer") {
				typealias Inner = SignalProducer<Int, TestError>
				typealias Outer = Signal<Int, NoError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatMap(.latest) { _ in inner }
					.assumeNoErrors()
					.observeValues { value in
						observed = value
					}
				
				outerObserver.send(value: 4)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with NoError and a NoError SignalProducer") {
				typealias Inner = SignalProducer<Int, NoError>
				typealias Outer = Signal<Int, NoError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatMap(.latest) { _ in inner }
					.observeValues { value in
						observed = value
					}
				
				outerObserver.send(value: 4)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with TestError and a NoError SignalProducer") {
				typealias Inner = SignalProducer<Int, NoError>
				typealias Outer = Signal<Int, TestError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatMap(.latest) { _ in inner }
					.assumeNoErrors()
					.observeValues { value in
						observed = value
					}
				
				outerObserver.send(value: 4)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}

			it("works with Property and any arbitrary error") {
				_ = Signal<Int, TestError>.empty
					.flatMap(.latest) { _ in Property(value: 0) }
			}

			it("works with Property and NoError") {
				_ = Signal<Int, NoError>.empty
					.flatMap(.latest) { _ in Property(value: 0) }
			}
		}
		
		describe("SignalProducer.flatMap()") {
			it("works with TestError and a TestError Signal") {
				typealias Inner = Signal<Int, TestError>
				typealias Outer = SignalProducer<Int, TestError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatMap(.latest) { _ in inner }
					.assumeNoErrors()
					.startWithValues { value in
						observed = value
					}
				
				outerObserver.send(value: 4)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with NoError and a TestError Signal") {
				typealias Inner = Signal<Int, TestError>
				typealias Outer = SignalProducer<Int, NoError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatMap(.latest) { _ in inner }
					.assumeNoErrors()
					.startWithValues { value in
						observed = value
					}
				
				outerObserver.send(value: 4)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with NoError and a NoError Signal") {
				typealias Inner = Signal<Int, NoError>
				typealias Outer = SignalProducer<Int, NoError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatMap(.latest) { _ in inner }
					.startWithValues { value in
						observed = value
					}
				
				outerObserver.send(value: 4)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with TestError and a NoError Signal") {
				typealias Inner = Signal<Int, NoError>
				typealias Outer = SignalProducer<Int, TestError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatMap(.latest) { _ in inner }
					.assumeNoErrors()
					.startWithValues { value in
						observed = value
					}
				
				outerObserver.send(value: 4)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with TestError and a TestError SignalProducer") {
				typealias Inner = SignalProducer<Int, TestError>
				typealias Outer = SignalProducer<Int, TestError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatMap(.latest) { _ in inner }
					.assumeNoErrors()
					.startWithValues { value in
						observed = value
					}
				
				outerObserver.send(value: 4)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with NoError and a TestError SignalProducer") {
				typealias Inner = SignalProducer<Int, TestError>
				typealias Outer = SignalProducer<Int, NoError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatMap(.latest) { _ in inner }
					.assumeNoErrors()
					.startWithValues { value in
						observed = value
					}
				
				outerObserver.send(value: 4)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with NoError and a NoError SignalProducer") {
				typealias Inner = SignalProducer<Int, NoError>
				typealias Outer = SignalProducer<Int, NoError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatMap(.latest) { _ in inner }
					.startWithValues { value in
						observed = value
					}
				
				outerObserver.send(value: 4)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}
			
			it("works with TestError and a NoError SignalProducer") {
				typealias Inner = SignalProducer<Int, NoError>
				typealias Outer = SignalProducer<Int, TestError>
				
				let (inner, innerObserver) = Inner.pipe()
				let (outer, outerObserver) = Outer.pipe()
				
				var observed: Int? = nil
				outer
					.flatMap(.latest) { _ in inner }
					.assumeNoErrors()
					.startWithValues { value in
						observed = value
					}
				
				outerObserver.send(value: 4)
				innerObserver.send(value: 4)
				expect(observed) == 4
			}

			it("works with Property and any arbitrary error") {
				_ = SignalProducer<Int, TestError>.empty
					.flatMap(.latest) { _ in Property(value: 0) }
			}

			it("works with Property and NoError") {
				_ = SignalProducer<Int, NoError>.empty
					.flatMap(.latest) { _ in Property(value: 0) }
			}
		}
		
		describe("Signal.merge()") {
			it("should emit values from all signals") {
				let (signal1, observer1) = Signal<Int, NoError>.pipe()
				let (signal2, observer2) = Signal<Int, NoError>.pipe()
				
				let mergedSignals = Signal.merge([signal1, signal2])
				
				var lastValue: Int?
				mergedSignals.observeValues { lastValue = $0 }
				
				expect(lastValue).to(beNil())
				
				observer1.send(value: 1)
				expect(lastValue) == 1
				
				observer2.send(value: 2)
				expect(lastValue) == 2
				
				observer1.send(value: 3)
				expect(lastValue) == 3
			}
			
			it("should not stop when one signal completes") {
				let (signal1, observer1) = Signal<Int, NoError>.pipe()
				let (signal2, observer2) = Signal<Int, NoError>.pipe()
				
				let mergedSignals = Signal.merge([signal1, signal2])
				
				var lastValue: Int?
				mergedSignals.observeValues { lastValue = $0 }
				
				expect(lastValue).to(beNil())
				
				observer1.send(value: 1)
				expect(lastValue) == 1
				
				observer1.sendCompleted()
				expect(lastValue) == 1
				
				observer2.send(value: 2)
				expect(lastValue) == 2
			}
			
			it("should complete when all signals complete") {
				let (signal1, observer1) = Signal<Int, NoError>.pipe()
				let (signal2, observer2) = Signal<Int, NoError>.pipe()
				
				let mergedSignals = Signal.merge([signal1, signal2])
				
				var completed = false
				mergedSignals.observeCompleted { completed = true }
				
				expect(completed) == false
				
				observer1.send(value: 1)
				expect(completed) == false
				
				observer1.sendCompleted()
				expect(completed) == false
				
				observer2.sendCompleted()
				expect(completed) == true
			}
		}
		
		describe("SignalProducer.merge()") {
			it("should emit values from all producers") {
				let (signal1, observer1) = SignalProducer<Int, NoError>.pipe()
				let (signal2, observer2) = SignalProducer<Int, NoError>.pipe()
				
				let mergedSignals = SignalProducer.merge([signal1, signal2])
				
				var lastValue: Int?
				mergedSignals.startWithValues { lastValue = $0 }
				
				expect(lastValue).to(beNil())
				
				observer1.send(value: 1)
				expect(lastValue) == 1
				
				observer2.send(value: 2)
				expect(lastValue) == 2
				
				observer1.send(value: 3)
				expect(lastValue) == 3
			}
			
			it("should not stop when one producer completes") {
				let (signal1, observer1) = SignalProducer<Int, NoError>.pipe()
				let (signal2, observer2) = SignalProducer<Int, NoError>.pipe()
				
				let mergedSignals = SignalProducer.merge([signal1, signal2])
				
				var lastValue: Int?
				mergedSignals.startWithValues { lastValue = $0 }
				
				expect(lastValue).to(beNil())
				
				observer1.send(value: 1)
				expect(lastValue) == 1
				
				observer1.sendCompleted()
				expect(lastValue) == 1
				
				observer2.send(value: 2)
				expect(lastValue) == 2
			}
			
			it("should complete when all producers complete") {
				let (signal1, observer1) = SignalProducer<Int, NoError>.pipe()
				let (signal2, observer2) = SignalProducer<Int, NoError>.pipe()
				
				let mergedSignals = SignalProducer.merge([signal1, signal2])
				
				var completed = false
				mergedSignals.startWithCompleted { completed = true }
				
				expect(completed) == false
				
				observer1.send(value: 1)
				expect(completed) == false
				
				observer1.sendCompleted()
				expect(completed) == false
				
				observer2.sendCompleted()
				expect(completed) == true
			}
		}

		describe("SignalProducer.prefix()") {
			it("should emit initial value") {
				let (signal, observer) = SignalProducer<Int, NoError>.pipe()

				let mergedSignals = signal.prefix(value: 0)

				var lastValue: Int?
				mergedSignals.startWithValues { lastValue = $0 }

				expect(lastValue) == 0

				observer.send(value: 1)
				expect(lastValue) == 1

				observer.send(value: 2)
				expect(lastValue) == 2

				observer.send(value: 3)
				expect(lastValue) == 3
			}

			it("should emit initial value") {
				let (signal, observer) = SignalProducer<Int, NoError>.pipe()
				
				let mergedSignals = signal.prefix(SignalProducer(value: 0))
				
				var lastValue: Int?
				mergedSignals.startWithValues { lastValue = $0 }
				
				expect(lastValue) == 0
				
				observer.send(value: 1)
				expect(lastValue) == 1
				
				observer.send(value: 2)
				expect(lastValue) == 2
				
				observer.send(value: 3)
				expect(lastValue) == 3
			}
		}
		
		describe("SignalProducer.concat(value:)") {
			it("should emit final value") {
				let (signal, observer) = SignalProducer<Int, NoError>.pipe()
				
				let mergedSignals = signal.concat(value: 4)
				
				var lastValue: Int?
				mergedSignals.startWithValues { lastValue = $0 }
								
				observer.send(value: 1)
				expect(lastValue) == 1
				
				observer.send(value: 2)
				expect(lastValue) == 2
				
				observer.send(value: 3)
				expect(lastValue) == 3
				
				observer.sendCompleted()
				expect(lastValue) == 4
			}
		}
	}
}
