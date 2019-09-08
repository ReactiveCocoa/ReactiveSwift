//
//  ReactiveSwiftTests.swift
//  SpeedTestTests
//
//  Created by Jakub Olejník on 08/08/2019.
//  Copyright © 2019 QuickBird Studios. All rights reserved.
//

import XCTest
import ReactiveSwift

let iterations = 10000

class ReactiveSwiftTests: XCTestCase {

	func testPublishSubjectPumping() {
		measure {
			var sum = 0
			let subject = Signal<Int, Never>.pipe()

			let subscription = subject.output
				.observeValues { x in
					sum += x
			}

			for _ in 0 ..< iterations * 100 {
				subject.input.send(value: 1)
			}

			subscription?.dispose()

			XCTAssertEqual(sum, iterations * 100)
		}
	}

	func testPublishSubjectPumpingTwoSubscriptions() {
		measure {
			var sum = 0
			let subject = Signal<Int, Never>.pipe()

			let subscription1 = subject.output
				.observeValues { x in
					sum += x
			}

			let subscription2 = subject.output
				.observeValues { x in
					sum += x
			}

			for _ in 0 ..< iterations * 100 {
				subject.input.send(value: 1)
			}

			subscription1?.dispose()
			subscription2?.dispose()

			XCTAssertEqual(sum, iterations * 100 * 2)
		}
	}

	func testPublishSubjectCreating() {
		measure {
			var sum = 0

			for _ in 0 ..< iterations * 10 {
				let subject = Signal<Int, Never>.pipe()

				let subscription = subject.output
					.observeValues { x in
						sum += x
				}

				for _ in 0 ..< 1 {
					subject.input.send(value: 1)
				}

				subscription?.dispose()
			}

			XCTAssertEqual(sum, iterations * 10)
		}
	}

	func testMapFilterPumping() {
		measure {
			var sum = 0

			let subscription = SignalProducer<Int, Never> { observer, _ in
				for _ in 0 ..< iterations * 10 {
					observer.send(value: 1)
				}
				}
				.map { $0 }.filter { _ in true }
				.map { $0 }.filter { _ in true }
				.map { $0 }.filter { _ in true }
				.map { $0 }.filter { _ in true }
				.map { $0 }.filter { _ in true }
				.map { $0 }.filter { _ in true }
				.startWithValues { x in
					sum += x
			}

			subscription.dispose()

			XCTAssertEqual(sum, iterations * 10)
		}
	}

	func testMapFilterCreating() {
		measure {
			var sum = 0

			for _ in 0 ..< iterations {
				let subscription = SignalProducer<Int, Never> { observer, _ in
					for _ in 0 ..< 1 {
						observer.send(value: 1)
					}
					}
					.map { $0 }.filter { _ in true }
					.map { $0 }.filter { _ in true }
					.map { $0 }.filter { _ in true }
					.map { $0 }.filter { _ in true }
					.map { $0 }.filter { _ in true }
					.map { $0 }.filter { _ in true }
					.startWithValues { x in
						sum += x
				}

				subscription.dispose()
			}

			XCTAssertEqual(sum, iterations)
		}
	}

	func testFlatMapsPumping() {
		measure {
			var sum = 0

			// need to create subexpressions, otherwise compiler is unable to type-check
			let partialProducer = SignalProducer<Int, Never> { observer, _ in
				for _ in 0 ..< iterations * 10 {
					observer.send(value: 1)
				}
				}
				.flatMap(.merge) { x in SignalProducer(value: x) }
				.flatMap(.merge) { x in SignalProducer(value: x) }
				.flatMap(.merge) { x in SignalProducer(value: x) }

			let subscription = partialProducer.flatMap(.merge) { x in SignalProducer(value: x) }
				.flatMap(.merge) { x in SignalProducer(value: x) }
				.startWithValues { x in
					sum += x
			}

			subscription.dispose()

			XCTAssertEqual(sum, iterations * 10)
		}
	}

	func testFlatMapsCreating() {
		measure {
			var sum = 0
			for _ in 0 ..< iterations {

				// need to create subexpressions, otherwise compiler is unable to type-check
				let partialProducer = SignalProducer<Int, Never> { observer, _ in
					for _ in 0 ..< 1 {
						observer.send(value: 1)
					}
					}
					.flatMap(.merge) { x in SignalProducer(value: x) }
					.flatMap(.merge) { x in SignalProducer(value: x) }
					.flatMap(.merge) { x in SignalProducer(value: x) }

				let subscription = partialProducer.flatMap(.merge) { x in SignalProducer(value: x) }
					.flatMap(.merge) { x in SignalProducer(value: x) }
					.startWithValues { x in
						sum += x
				}

				subscription.dispose()
			}

			XCTAssertEqual(sum, iterations)
		}
	}

	func testFlatMapLatestPumping() {
		measure {
			var sum = 0

			// need to create subexpressions, otherwise compiler is unable to type-check
			let partialProducer = SignalProducer<Int, Never> { observer, _ in
				for _ in 0 ..< iterations * 10 {
					observer.send(value: 1)
				}
				}
				.flatMap(.latest) { x in SignalProducer(value: x) }
				.flatMap(.latest) { x in SignalProducer(value: x) }
				.flatMap(.latest) { x in SignalProducer(value: x) }

			let subscription = partialProducer.flatMap(.latest) { x in SignalProducer(value: x) }
				.flatMap(.latest) { x in SignalProducer(value: x) }
				.startWithValues { x in
					sum += x
			}

			subscription.dispose()

			XCTAssertEqual(sum, iterations * 10)
		}
	}

	func testFlatMapLatestCreating() {
		measure {
			var sum = 0
			for _ in 0 ..< iterations {
				// need to create subexpressions, otherwise compiler is unable to type-check
				let partialProducer = SignalProducer<Int, Never> { observer, _ in
					for _ in 0 ..< 1 {
						observer.send(value: 1)
					}
					}
					.flatMap(.latest) { x in SignalProducer(value: x) }
					.flatMap(.latest) { x in SignalProducer(value: x) }
					.flatMap(.latest) { x in SignalProducer(value: x) }

				let subscription = partialProducer.flatMap(.latest) { x in SignalProducer(value: x) }
					.flatMap(.latest) { x in SignalProducer(value: x) }
					.startWithValues { x in
						sum += x
				}

				subscription.dispose()
			}

			XCTAssertEqual(sum, iterations)
		}
	}

	func testCombineLatestPumping() {
		measure {
			var sum = 0
			var last = SignalProducer<Int, Never>.combineLatest(
				SignalProducer(value: 1), SignalProducer(value: 1), SignalProducer(value: 1),
				SignalProducer<Int, Never> { observer, _ in
					for _ in 0 ..< iterations * 10 {
						observer.send(value: 1)
					}
			})
				.map { x, _, _ ,_ in x }

			for _ in 0 ..< 6 {
				last = SignalProducer.combineLatest(SignalProducer(value: 1), SignalProducer(value: 1), SignalProducer(value: 1), last)
					.map { x, _, _ ,_ in x }
			}

			let subscription = last
				.startWithValues { x in
					sum += x
			}

			subscription.dispose()

			XCTAssertEqual(sum, iterations * 10)
		}
	}

	func testCombineLatestCreating() {
		measure {
			var sum = 0
			for _ in 0 ..< iterations {
				var last = SignalProducer<Int, Never>.combineLatest(
					SignalProducer(value: 1), SignalProducer(value: 1), SignalProducer(value: 1),
					SignalProducer<Int, Never> { observer, _ in
						for _ in 0 ..< 1 {
							observer.send(value: 1)
						}
				})
					.map { x, _, _ ,_ in x }

				for _ in 0 ..< 6 {
					last = SignalProducer.combineLatest(SignalProducer(value: 1), SignalProducer(value: 1), SignalProducer(value: 1), last)
						.map { x, _, _ ,_ in x }
				}

				let subscription = last
					.startWithValues { x in
						sum += x
				}

				subscription.dispose()
			}

			XCTAssertEqual(sum, iterations)
		}
	}
}
