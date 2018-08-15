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

protocol Thenable {
    associatedtype Value
    associatedtype Error: Swift.Error
    
    func await(notify: @escaping (PromiseResult<Value, Error>) -> Void) -> Disposable
}

extension Thenable {
    
    @discardableResult
    func chain<T: Thenable>(on: Scheduler = ImmediateScheduler(), body: @escaping (PromiseResult<Value, Error>) -> T) -> Promise<T.Value, Error> where T.Error == Error {
        return Promise<T.Value, Error> { resolve in
            return self.await { result in
                on.schedule {
                    let thenable = body(result)
                    thenable.await(notify: resolve)
                }
            }
        }
    }
    
    @discardableResult
    func then<T: Thenable>(on: Scheduler = ImmediateScheduler(), body: @escaping (Value) -> T) -> Promise<T.Value, Error> where T.Error == Error {
        
        return self.chain { (result) -> T in
            guard let value = result.value else {
                return Promise<T.Value, Error>(error: result.error) as! T
            }
            return body(value)
        }
        
    }
}

struct Promise<Value, Error: Swift.Error>: Thenable, SignalProducerConvertible {
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
        return SignalProducer { [weak state] observer, lifetime in
            guard let state = state else {
                observer.sendInterrupted()
                return
            }
            
            lifetime += state.producer.startWithValues {
                guard case .resolved(let result) = $0 else {
                    return
                }
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
    
    init(_ resolver: @escaping (@escaping (Result) -> Void) -> Disposable) {
        let promiseResolver = SignalProducer<State, NoError> { observer, lifetime in
            lifetime += resolver { result in
                observer.send(value: .resolved(result))
                observer.sendCompleted()
            }
        }
        state = Property(initial: .pending, then: promiseResolver)
    }
    
    init(_ resolver: @escaping (@escaping (Value) -> Void, @escaping (Error) -> Void) -> Disposable) {
        self.init { resolve in
            return resolver(
                { resolve(.fulfilled($0)) },
                { resolve(.rejected($0)) }
            )
        }
    }
    
    init(value: Value) {
        self.init(result: .fulfilled(value))
    }
    
    init(error: Error?) {
        self.init(result: .rejected(error))
    }
    
    init(result: Result) {
        state = Property(initial: .resolved(result), then: .empty)
    }
    
    init(producer: SignalProducer<Value, Error>) {
        self.init { resolve in
            return producer.start { event in
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
    
    func await(notify: @escaping (PromiseResult<Value, Error>) -> Void) -> Disposable {
        return state.producer
            .filterMap { $0.promiseResult }
            .startWithValues(notify)
    }
}



extension SignalProducer {
    func makePromise() -> Promise<Value, Error> {
        return Promise<Value, Error>(producer: self)
    }
}

func add28(to term: Int) -> Promise<Int, NoError> {
    return Promise { fulfil, _ in
        fulfil(term + 28)
        return AnyDisposable()
    }
}

let answer = SignalProducer<Int, NoError>(value: 14)
    .makePromise()
    .then { add28(to: $0) }

answer.await { (result) in
    print(result)
}

