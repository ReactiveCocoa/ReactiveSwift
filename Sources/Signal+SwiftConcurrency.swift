//
//  Signal+SwiftConcurrency.swift
//  ReactiveSwift
//
//  Created by Marco Cancellieri on 2021-11-11.
//  Copyright (c) 2021 GitHub. All rights reserved.
//
#if compiler(>=5.5) && canImport(_Concurrency)
import Foundation

@available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
extension Signal {
    public var asyncThrowingStream: AsyncThrowingStream<Value, Swift.Error> {
        AsyncThrowingStream<Value, Swift.Error> { continuation in
            let disposable = observe { event in
                switch event {
                case .value(let value):
                    continuation.yield(value)
                case .completed, .interrupted:
                    continuation.finish()
                case .failed(let error):
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable termination in
                disposable?.dispose()
            }
        }
    }
}

extension Signal where Error == Never {
    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    public var asyncStream: AsyncStream<Value> {
        AsyncStream<Value> { continuation in
            let disposable = observe { event in
                switch event {
                case .value(let value):
                    continuation.yield(value)
                case .completed, .interrupted:
                    continuation.finish()
                case .failed:
                    fatalError("Never is impossible to construct")
                }
            }
            continuation.onTermination = { @Sendable termination in
                disposable?.dispose()
            }
        }
    }
}
#endif
