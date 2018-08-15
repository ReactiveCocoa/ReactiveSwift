/*:
 > # IMPORTANT: To use `ReactiveSwift.playground`, please:
 
 1. Retrieve the project dependencies using one of the following terminal commands from the ReactiveSwift project root directory:
    - `git submodule update --init`
 **OR**, if you have [Carthage](https://github.com/Carthage/Carthage) installed
    - `carthage checkout`
 1. Open `ReactiveSwift.xcworkspace`
 1. Build `Result-Mac` scheme
 1. Build `ReactiveSwift-macOS` scheme
 1. Finally open the `ReactiveSwift.playground`
 1. Choose `View > Show Debug Area`
 */

import Result
import ReactiveSwift
import Foundation

/*:
 ## Sandbox
 
 A place where you can build your sand castles 🏖.
*/

enum PromiseResult<Value, Error: Swift.Error> {
    case fulfilled(Value)
    case rejected(Error?)   // nil error means that the producer was interrupted or empty
    
    init(value: Value) {
        self = .fulfilled(value)
    }
    
    init(error: Error?) {
        self = .rejected(error)
    }
    
    var value: Value? {
        switch self {
        case .fulfilled(let value): return value
        case .rejected(_): return nil
        }
    }
    
    var error: Error? {
        switch self {
        case .fulfilled(_): return nil
        case .rejected(let error): return error
        }
    }
}

protocol ThenableType {
    associatedtype Value
    associatedtype Error: Swift.Error
    
    func await(notify: @escaping (PromiseResult<Value, Error>) -> Void) -> Disposable
}

struct Thenable<Value, Error: Swift.Error>: ThenableType {
    typealias AwaitFunction = (@escaping (PromiseResult<Value, Error>) -> Void) -> Disposable
    typealias Result = PromiseResult<Value, Error>
    
    private let awaitImpl: AwaitFunction
    
    @inline(__always)
    func await(notify: @escaping (Result) -> Void) -> Disposable {
        return awaitImpl(notify)
    }
    
    init(_ impl: @escaping AwaitFunction) {
        self.awaitImpl = impl
    }
    
    init<T: ThenableType>(_ thenable: T) where T.Value == Value, T.Error == Error {
        self.awaitImpl = { notify in
            return thenable.await(notify: notify)
        }
    }
}

extension Thenable {
    init(_ result: Result) {
        self.init { notify in
            notify(result)
            return AnyDisposable()
        }
    }
    init(_ value: Value) {
        self.init(.fulfilled(value))
    }
    init(_ error: Error?) {
        self.init(.rejected(error))
    }
    
    static func never() -> Thenable<Value, Error> {
        return Thenable { _ in AnyDisposable() }
    }
}

extension ThenableType {
    @discardableResult
    func chain<T: ThenableType>(on: Scheduler = ImmediateScheduler(), body: @escaping (PromiseResult<Value, Error>) -> T) -> Promise<T.Value, Error> where T.Error == Error{
        return Promise<T.Value, Error> { resolve, lifetime in
            lifetime += self.await { result in
                on.schedule {
                    let thenable = body(result)
                    thenable.await(notify: resolve)
                }
            }
        }
    }
    
    @discardableResult
    func then<T: ThenableType>(on: Scheduler = ImmediateScheduler(), body: @escaping (Value) -> T) -> Promise<T.Value, Error> where T.Error == Error {
        
        return self.chain { result -> Thenable<T.Value, Error> in
            guard case .fulfilled(let value) = result else {
                return Thenable(result.error)
            }
            return Thenable(body(value))
        }
    }
}

struct Promise<Value, Error: Swift.Error>: ThenableType, SignalProducerConvertible {
    typealias Result = PromiseResult<Value, Error>
    
    enum State {
        case pending
        case resolved(Result)
        
        var promiseResult: Result? {
            switch self {
            case .pending: return nil
            case .resolved(let result): return result
            }
        }
    }
    
    private let state: Property<State>
    
    private let (_lifetime, _lifetimeToken) = Lifetime.make()
    
    var lifetime: Lifetime { return _lifetime }
    
    var producer: SignalProducer<Value, Error> {
        return SignalProducer(self)
    }
    
    fileprivate init(_ state: Property<State>) {
        self.state = state
    }
    
    func await(notify: @escaping (PromiseResult<Value, Error>) -> Void) -> Disposable {
        return state.producer
            .filterMap { $0.promiseResult }
            .startWithValues(notify)
    }
    
    static var never: Promise<Value, Error> {
        return Promise(Property(initial: .pending, then: .empty))
    }
}

extension Promise {
    init(_ resolver: @escaping (@escaping (Result) -> Void, Lifetime) -> Void) {
        let promiseResolver = SignalProducer<State, NoError> { observer, lifetime in
            resolver(
                {
                    result in
                    observer.send(value: .resolved(result))
                    observer.sendCompleted()
            },
                lifetime
            )
        }
        self.init(Property(initial: .pending, then: promiseResolver))
    }
    
    init(_ resolver: @escaping (@escaping (Value) -> Void, @escaping (Error) -> Void, Lifetime) -> Void) {
        self.init { resolve, lifetime in
            resolver (
                { resolve(.fulfilled($0)) },
                { resolve(.rejected($0)) },
                lifetime
            )
        }
    }
}

extension Promise {
    
    init(_ result: Result) {
        self.init(Property(initial: .resolved(result), then: .empty))
    }
    
    init(_ value: Value) {
        self.init(.fulfilled(value))
    }
    
    init(_ error: Error?) {
        self.init(.rejected(error))
    }
}

extension Promise {
    init(_ producer: SignalProducer<Value, Error>) {
        self.init { resolve, lifetime in
            lifetime += producer.start { event in
                switch event {
                case .value(let value):
                    resolve(.fulfilled(value))
                case .failed(let error):
                    resolve(.rejected(error))
                case .completed, .interrupted:
                    // this one will be ignored if real value/error was delivered first
                    resolve(.rejected(nil))
                }
            }
        }
    }
}

extension SignalProducer {
    init<T: ThenableType>(thenable: T) where T.Value == Value, T.Error == Error {
        self.init { observer, lifetime in
            lifetime += thenable.await { result in
                switch result {
                case .fulfilled(let value):
                    observer.send(value: value)
                    observer.sendCompleted()
                case .rejected(let error?):
                    observer.send(error: error)
                case .rejected(nil):
                    observer.sendCompleted()
                }
            }
        }
    }
    
    init<T: ThenableType>(_ thenable: T) where T.Value == Value, T.Error == Error {
        self.init(thenable: thenable)
    }
    
    init(_ promise: Promise<Value, Error>) {
        self.init(thenable: promise)
    }
}

extension SignalProducer {
    func makePromise() -> Promise<Value, Error> {
        return Promise<Value, Error>(self)
    }
}

func add28(to term: Int) -> Promise<Int, NoError> {
    return Promise { fulfil, _, _ in
        fulfil(term + 28)
    }
}

let answer = SignalProducer<Int, NoError>(value: 14)
    .makePromise()
    .then { add28(to: $0) }

answer.await { (result) in
    print(result)
}

