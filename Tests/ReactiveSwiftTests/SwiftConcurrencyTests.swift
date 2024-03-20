//
//  SwiftConcurrencyTests.swift
//  ReactiveSwift
//
//  Created by Marco Cancellieri on 2021-11-11.
//  Copyright (c) 2021 GitHub. All rights reserved.
//

#if compiler(>=5.5.2) && canImport(_Concurrency)
import Foundation
import ReactiveSwift
import XCTest

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, *)
class SwiftConcurrencyTests: XCTestCase {
	func testValuesAsyncSignalProducer() async {
		let values = [1,2,3]
		var sum = 0
		let asyncStream = SignalProducer(values).asyncStream
		for await number in asyncStream {
			sum += number
		}
		XCTAssertEqual(sum, 6)
	}
	
	func testValuesAsyncThrowingSignalProducer() async throws {
		let values = [1,2,3]
		var sum = 0
		let asyncStream = SignalProducer(values).asyncThrowingStream
		for try await number in asyncStream {
			sum += number
		}
		XCTAssertEqual(sum, 6)
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
			DispatchQueue.main.async {
				for number in [1, 2, 3] {
					observer.send(value: number)
				}
				observer.sendCompleted()
			}
		}
		var sum = 0
		let asyncStream = signal.asyncStream
		for await number in asyncStream {
			sum += number
		}
		XCTAssertEqual(sum, 6)
	}
	
	func testValuesAsyncThrowingSignal() async throws {
		let signal = Signal<Int, Never> { observer, _ in
			DispatchQueue.main.async {
				for number in [1, 2, 3] {
					observer.send(value: number)
				}
				observer.sendCompleted()
			}
		}
		var sum = 0
		let asyncStream = signal.asyncThrowingStream
		for try await number in asyncStream {
			sum += number
		}
		XCTAssertEqual(sum, 6)
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
			DispatchQueue.main.async {
				observer.send(error: error)
			}
		}
		let asyncStream = signal.asyncThrowingStream
		await XCTAssertThrowsError(try await asyncStream.first(where: { _ in true }))
	}
}
// Extension to allow Throw assertion for async expressions
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, *)
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
