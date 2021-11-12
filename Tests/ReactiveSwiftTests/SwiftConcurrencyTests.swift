//
//  SwiftConcurrencyTests.swift
//  ReactiveSwift
//
//  Created by Marco Cancellieri on 2021-11-11.
//  Copyright (c) 2021 GitHub. All rights reserved.
//

#if compiler(>=5.5) && canImport(_Concurrency)
import Foundation
import ReactiveSwift
import XCTest

@available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
class SwiftConcurrencyTests: XCTestCase {
    func testValuesAsyncSignalProducer() async {
        let values = [1,2,3]
        var counter = 0
        let asyncStream = SignalProducer(values).asyncStream
        for await _ in asyncStream {
            counter += 1
        }
        XCTAssertEqual(counter, 3)
    }

    func testValuesAsyncThrowingSignalProducer() async throws {
        let values = [1,2,3]
        var counter = 0
        let asyncStream = SignalProducer(values).asyncThrowingStream
        for try await _ in asyncStream {
            counter += 1
        }
        XCTAssertEqual(counter, 3)
    }

    func testCompleteAsyncSignalProducer() async {
        let asyncStream = SignalProducer<String, Never>.empty.asyncStream
        let first = await asyncStream.first(where: { _ in true })
        XCTAssertEqual(first, nil)
    }

    func testCompleteAsyncThrowingSignalProducer() async throws {
        let asyncStream = SignalProducer<String, Error>.empty.asyncThrowingStream
        let first = try await asyncStream.first(where: { _ in true })
        XCTAssertEqual(first, nil)
    }

    func testErrorSignalProducer() async {
        let error = NSError(domain: "domain", code: 0, userInfo: nil)
        let asyncStream = SignalProducer<String, Error>(error: error).asyncThrowingStream
        await XCTAssertThrowsError(try await asyncStream.first(where: { _ in true }))
    }

    func testValuesAsyncSignal() async {
        let signal = Signal<Int, Never> { observer, _ in
            Task {
                for number in [1, 2, 3] {
                    observer.send(value: number)
                }
                observer.sendCompleted()
            }
        }
        var counter = 0
        let asyncStream = signal.asyncStream
        for await _ in asyncStream {
            counter += 1
        }
        XCTAssertEqual(counter, 3)
    }

    func testValuesAsyncThrowingSignal() async throws {
        let signal = Signal<Int, Never> { observer, _ in
            Task {
                for number in [1, 2, 3] {
                    observer.send(value: number)
                }
                observer.sendCompleted()
            }
        }
        var counter = 0
        let asyncStream = signal.asyncThrowingStream
        for try await _ in asyncStream {
            counter += 1
        }
        XCTAssertEqual(counter, 3)
    }

    func testCompleteAsyncSignal() async {
        let asyncStream = Signal<String, Never>.empty.asyncStream
        let first = await asyncStream.first(where: { _ in true })
        XCTAssertEqual(first, nil)
    }

    func testCompleteAsyncThrowingSignal() async throws {
        let asyncStream = Signal<String, Error>.empty.asyncThrowingStream
        let first = try await asyncStream.first(where: { _ in true })
        XCTAssertEqual(first, nil)
    }

    func testErrorSignal() async {
        let error = NSError(domain: "domain", code: 0, userInfo: nil)
        let signal = Signal<String, Error> { observer, _ in
            Task {
                observer.send(error: error)
            }
        }
        let asyncStream = signal.asyncThrowingStream
        await XCTAssertThrowsError(try await asyncStream.first(where: { _ in true }))
    }
}
// Extension to allow Throw assertion for async expressions
@available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
fileprivate extension XCTest {
    func XCTAssertThrowsError<T: Sendable>(
        _ expression: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ errorHandler: (_ error: Error) -> Void = { _ in }
    ) async {
        do {
            _ = try await expression()
            XCTFail(message(), file: file, line: line)
        } catch {
            errorHandler(error)
        }
    }
}

#endif
