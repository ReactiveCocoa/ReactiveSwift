//
//  SignalTests.swift
//  Rex
//
//  Created by Neil Pankey on 5/9/15.
//  Copyright (c) 2015 Neil Pankey. All rights reserved.
//

import ReactiveSwift
import XCTest
import enum Result.NoError

final class SignalTests: XCTestCase {

    func testFilterMap() {
        let (signal, observer) = Signal<Int, NoError>.pipe()
        var values: [String] = []

        signal
            .filterMap {
                return $0 % 2 == 0 ? String($0) : nil
            }
            .observeValues { values.append($0) }

        observer.send(value: 1)
        XCTAssert(values == [])

        observer.send(value: 2)
        XCTAssert(values == ["2"])

        observer.send(value: 3)
        XCTAssert(values == ["2"])

        observer.send(value: 6)
        XCTAssert(values == ["2", "6"])
    }

    func testIgnoreErrorCompletion() {
        let (signal, observer) = Signal<Int, TestError>.pipe()
        var completed = false

        signal
            .ignoreError()
            .observeCompleted { completed = true }

        observer.send(value: 1)
        XCTAssertFalse(completed)

        observer.send(error: .default)
        XCTAssertTrue(completed)
    }

    func testIgnoreErrorInterruption() {
        let (signal, observer) = Signal<Int, TestError>.pipe()
        var interrupted = false

        signal
            .ignoreError(replacement: .interrupted)
            .observeInterrupted { interrupted = true }

        observer.send(value: 1)
        XCTAssertFalse(interrupted)

        observer.send(error: .default)
        XCTAssertTrue(interrupted)
    }

    func testTimeoutAfterTerminating() {
        let scheduler = TestScheduler()
        let (signal, observer) = Signal<Int, NoError>.pipe()
        var interrupted = false
        var completed = false

        signal
            .timeout(after: 2, with: .interrupted, on: scheduler)
            .observe(Observer(
                completed: { completed = true },
                interrupted: { interrupted = true }
            ))

        scheduler.schedule(after: 1) { observer.sendCompleted() }

        XCTAssertFalse(interrupted)
        XCTAssertFalse(completed)

        scheduler.run()
        XCTAssertTrue(completed)
        XCTAssertFalse(interrupted)
    }

    func testTimeoutAfterTimingOut() {
        let scheduler = TestScheduler()
        let (signal, observer) = Signal<Int, NoError>.pipe()
        var interrupted = false
        var completed = false

        signal
            .timeout(after: 2, with: .interrupted, on: scheduler)
            .observe(Observer(
                completed: { completed = true },
                interrupted: { interrupted = true }
            ))

        scheduler.schedule(after: 3) { observer.sendCompleted() }

        XCTAssertFalse(interrupted)
        XCTAssertFalse(completed)

        scheduler.run()
        XCTAssertTrue(interrupted)
        XCTAssertFalse(completed)
    }

    func testUncollect() {
        let (signal, observer) = Signal<[Int], NoError>.pipe()
        var values: [Int] = []

        signal
            .uncollect()
            .observeValues { values.append($0) }

        observer.send(value: [])
        XCTAssert(values.isEmpty)

        observer.send(value: [1])
        XCTAssert(values == [1])

        observer.send(value: [2, 3])
        XCTAssert(values == [1, 2, 3])
    }

    func testMuteForValues() {
        let scheduler = TestScheduler()
        let (signal, observer) = Signal<Int, NoError>.pipe()
        var value = -1

        signal
            .mute(for: 1, clock: scheduler)
            .observeValues { value = $0 }

        scheduler.schedule { observer.send(value: 1) }
        scheduler.advance()
        XCTAssertEqual(value, 1)

        scheduler.schedule { observer.send(value: 2) }
        scheduler.advance()
        XCTAssertEqual(value, 1)

        scheduler.schedule { observer.send(value: 3) }
        scheduler.schedule { observer.send(value: 4) }
        scheduler.advance()
        XCTAssertEqual(value, 1)

        scheduler.advance(by: 1)
        XCTAssertEqual(value, 1)

        scheduler.schedule { observer.send(value: 5) }
        scheduler.schedule { observer.send(value: 6) }
        scheduler.advance()
        XCTAssertEqual(value, 5)
    }

    func testMuteForFailure() {
        let scheduler = TestScheduler()
        let (signal, observer) = Signal<Int, TestError>.pipe()
        var value = -1
        var failed = false

        signal
            .mute(for: 1, clock: scheduler)
            .observe(Observer(
                value: { value = $0 },
                failed: { _ in failed = true }
            ))

        scheduler.schedule { observer.send(value: 1) }
        scheduler.advance()
        XCTAssertEqual(value, 1)

        scheduler.schedule { observer.send(value: 2) }
        scheduler.schedule { observer.send(error: .default) }
        scheduler.advance()
        XCTAssertTrue(failed)
        XCTAssertEqual(value, 1)
    }
}
