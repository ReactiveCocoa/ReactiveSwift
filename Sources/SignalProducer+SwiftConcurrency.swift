//
//  SignalProducer+SwiftConcurrency.swift
//  ReactiveSwift
//
//  Created by Marco Cancellieri on 2021-11-11.
//  Copyright (c) 2021 GitHub. All rights reserved.
//
#if compiler(>=5.5.2) && canImport(_Concurrency)
import Foundation

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, *)
extension SignalProducer {
	public var asyncThrowingStream: AsyncThrowingStream<Value, Swift.Error> {
		AsyncThrowingStream<Value, Swift.Error> { continuation in
			let disposable = start { event in
				switch event {
				case .value(let value):
					continuation.yield(value)
				case .completed, .interrupted:
					continuation.finish()
				case .failed(let error):
					continuation.finish(throwing: error)
				}
			}
			continuation.onTermination = { @Sendable _ in
				disposable.dispose()
			}
		}
	}
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, *)
extension SignalProducer where Error == Never {
	public var asyncStream: AsyncStream<Value> {
		AsyncStream<Value> { continuation in
			let disposable = start { event in
				switch event {
				case .value(let value):
					continuation.yield(value)
				case .completed, .interrupted:
					continuation.finish()
				case .failed:
					fatalError("Never is impossible to construct")
				}
			}
			continuation.onTermination = { @Sendable _ in
				disposable.dispose()
			}
		}
	}
}
#endif
