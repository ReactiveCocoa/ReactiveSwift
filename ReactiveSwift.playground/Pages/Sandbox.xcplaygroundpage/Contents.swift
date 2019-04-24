
import ReactiveSwift
import Foundation


//enum AsyncError<Error: Swift.Error>: Swift.Error {
//    case rejected(Error)
//    case interrupted
//}

protocol Awaitable {
    associatedtype Value
    associatedtype Error: Swift.Error
    typealias AsyncResult = Result<Value, Error>
    
    func await(notify: @escaping (AsyncResult) -> Void) -> Disposable
}

protocol AsyncValueType: Awaitable {
    
    typealias ResolveCallback = (AsyncResult) -> Void
    
    init(_ resolver: @escaping (@escaping ResolveCallback, Lifetime) -> Void)
    init(_ producer: SignalProducer<Value, Error>)

}

extension AsyncValueType {
    init<A: Awaitable>(_ awaitable: A) where A.Value == Value, A.Error == Error  {
        self.init { resolve, lifetime in
            lifetime += awaitable.await(notify: resolve)
        }
    }
    init(_ value: Value) {
        self.init { resolve, _ in resolve(.success(value)) }
    }
    init(_ error: Error) {
        self.init { resolve, _ in resolve(.failure(error)) }
    }
    init(_ result: Result<Value, Error>) {
        self.init { resolve, _ in resolve(result) }
    }
}

class AsyncValue<Value, Error: Swift.Error>: AsyncValueType {
    
    // without this swift segfaults :/
    typealias AsyncResult = Result<Value, Error>
    
    enum State {
        case pending
        case resolved(AsyncResult)
        
        var asyncResult: AsyncResult? {
            switch self {
            case .pending: return nil
            case .resolved(let result): return result
            }
        }
    }
    
    private let state: Property<State>
    
    fileprivate init(state: Property<State>) {
        self.state = state
    }
    
    func await(notify: @escaping (AsyncResult) -> Void) -> Disposable {
        return state.producer
            .filterMap { $0.asyncResult }
            .startWithValues(notify)
    }
    
    required convenience init(_ resolver: @escaping (@escaping ResolveCallback, Lifetime) -> Void) {
        let resolvingProducer = SignalProducer<State, Never> { obs, life in
            func resolve(_ result: Result<Value, Error>) {
                switch result {
                case .success(let value): obs.send(value: .resolved(.success(value)))
                case .failure(let error): obs.send(value: .resolved(.failure(error)))
                }
                obs.sendCompleted()
            }
            resolver(resolve, life)
        }
        self.init(state: Property<State>(initial: .pending, then: resolvingProducer))
    }
    
    required convenience init(_ producer: SignalProducer<Value, Error>) {
        self.init { resolve, lifetime in
            lifetime += producer.startWithResult(resolve)
        }
    }
    
    deinit {
        print("\(type(of:self)) deinit")
    }
}

class AsyncValueProducer<Value, Error: Swift.Error>: AsyncValueType {
    
    private let producer: SignalProducer<Value, Error>
    
    fileprivate init(producer: SignalProducer<Value, Error>) {
        self.producer = producer
    }
    
    func await(notify: @escaping (AsyncResult) -> Void) -> Disposable {
        return producer.startWithResult(notify)
    }
    
    required convenience init(_ resolver: @escaping (@escaping ResolveCallback, Lifetime) -> Void) {
        let resolvingProducer = SignalProducer<Value, Error> { obs, life in
            func resolve(_ result: Result<Value, Error>) {
                switch result {
                case .success(let value):
                    obs.send(value: value)
                    obs.sendCompleted()
                case .failure(let error):
                    obs.send(error: error)
                }
            }
            resolver(resolve, life)
        }
        self.init(producer: resolvingProducer)
    }
    
    required convenience init(_ producer: SignalProducer<Value, Error>) {
        self.init(producer: producer.take(first: 1))
    }
    
    deinit {
        print("\(type(of:self)) deinit")
    }
}


extension AsyncValueProducer {
    func start() -> AsyncValue<Value, Error> {
        return AsyncValue(self)
    }
}


extension AsyncValueType {
    func when(ready onReady: (@escaping (Value) -> Void), error onError: ((Error) -> Void)? = nil) -> Self {
        return Self { (resolve, lifetime) in
            lifetime += self.await { result in
                switch result {
                case .failure(let error): onError?(error)
                case .success(let value): onReady(value)
                }
                resolve(result)
            }
        }
    }
    
    func map<T: AsyncValueType>(_ transform: @escaping (Value) -> T) -> T where T.Error == Error {
        return T { (resolve, lifetime) in
            lifetime += self.await { result in
                switch result {
                case .failure(let error): resolve(.failure(error))
                case .success(let value):
                    lifetime += transform(value).await(notify: resolve)
                }
            }
        }
    }
}



var seed = 0

let seedProducer = SignalProducer<Int, Never> { obs, _ in
    obs.send(value: seed)
}

let test = {
    let value =
        AsyncValueProducer(seedProducer)
        .map {
            // try changing the below between AsyncValue and AsyncValueProducer
            // AsyncValue($0 + 10)
            AsyncValueProducer($0 + 10)
            
            // NB! Returnign an AsyncValue immediately starts the mapped producer
            // because an AsyncValue is a hot signal, and it will need to start the
            // producer in order to try an resolve its value
        }
        .when(ready: { print("resolved with value \($0)") })
    
    print("incrementing seed")
    seed += 1

    print("awaiting result")
    value.await(notify: { print("await notified with \($0)") })
}

test()
print("end")
