import Foundation
import Dispatch
import Result

// MARK: Unavailable methods in ReactiveSwift 2.0.
extension AnyDisposable {
	@available(*, unavailable, renamed:"init(_:)")
	public convenience init(action: @escaping () -> Void) { fatalError() }
}

extension Signal {
	@available(*, unavailable, renamed:"promoteError")
	public func promoteErrors<F>(_: F.Type) -> Signal<Value, F> { fatalError() }
}

extension SignalProducer {
	@available(*, unavailable, renamed:"promoteError")
	public func promoteErrors<F>(_: F.Type) -> SignalProducer<Value, F> { fatalError() }
}

extension Lifetime {
	@available(*, unavailable, renamed:"hasEnded")
	public var isDisposed: Bool { fatalError() }

	@discardableResult
	@available(*, unavailable, renamed:"observeEnded(_:)")
	public func add(_ action: () -> Void) -> Disposable? { fatalError() }

	@discardableResult
	@available(*, unavailable, message:"Use `observeEnded(_:)` instead.")
	public static func += (left: Lifetime, right: () -> Void) -> Disposable? { fatalError() }

	@discardableResult
	@available(*, deprecated, message:"Use `observeEnded(_:)` with a method reference to `dispose()` instead. This method is subject to removal in a future release.")
	public func add(_ d: Disposable?) -> Disposable? {
		return d.flatMap { observeEnded($0.dispose) }
	}
}

extension SignalProducer {
	@available(*, unavailable, renamed:"init(_:)")
	public static func attempt(_ operation: @escaping () -> Result<Value, Error>) -> SignalProducer<Value, Error> { fatalError() }
}

extension SignalProducer where Error == AnyError {
	@available(*, unavailable, renamed:"init(_:)")
	public static func attempt(_ operation: @escaping () throws -> Value) -> SignalProducer<Value, Error> { fatalError() }
}

extension PropertyProtocol {
	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<P: PropertyProtocol>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> P) -> Property<P.Value> { fatalError() }
}

extension Signal {
	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> Inner) -> Signal<Inner.Value, Error> where Error == Inner.Error { fatalError() }

	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> Inner) -> Signal<Inner.Value, Error> where Inner.Error == NoError { fatalError() }
}

extension Signal where Error == NoError {
	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> Inner) -> Signal<Inner.Value, Inner.Error> where Error == Inner.Error { fatalError() }

	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> Inner) -> Signal<Inner.Value, Inner.Error> { fatalError() }
}

extension SignalProducer {
	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> Inner) -> SignalProducer<Inner.Value, Error> where Error == Inner.Error { fatalError() }

	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> Inner) -> SignalProducer<Inner.Value, Error> where Inner.Error == NoError { fatalError() }
}

extension SignalProducer where Error == NoError {
	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> Inner) -> SignalProducer<Inner.Value, Inner.Error> where Error == Inner.Error { fatalError() }

	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<Inner: SignalProducerConvertible>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> Inner) -> SignalProducer<Inner.Value, Inner.Error> { fatalError() }
}

extension ComposableMutablePropertyProtocol {
	@available(*, unavailable, renamed:"withValue(_:)")
	public func withValue<Result>(action: (Value) throws -> Result) rethrows -> Result { fatalError() }
}

extension SignalProducer {
	@available(*, unavailable, renamed:"attempt(_:)")
	public func attempt(action: @escaping (Value) -> Result<(), Error>) -> SignalProducer<Value, Error> { fatalError() }
}

extension CompositeDisposable {
	@available(*, unavailable, message:"Use `Disposable?` instead.")
	public typealias DisposableHandle = Disposable?
}

extension Optional where Wrapped == Disposable {
	@available(*, unavailable, renamed:"dispose")
	public func remove() { fatalError() }
}

@available(*, unavailable, renamed:"SignalProducer.timer")
public func timer(interval: DispatchTimeInterval, on scheduler: DateScheduler) -> SignalProducer<Date, NoError> { fatalError() }

@available(*, unavailable, renamed:"SignalProducer.timer")
public func timer(interval: DispatchTimeInterval, on scheduler: DateScheduler, leeway: DispatchTimeInterval) -> SignalProducer<Date, NoError> { fatalError() }

// MARK: Obsolete types in ReactiveSwift 2.0.
@available(*, unavailable, renamed:"AnyDisposable")
public typealias SimpleDisposable = AnyDisposable

@available(*, unavailable, renamed:"AnyDisposable")
public typealias ActionDisposable = AnyDisposable

@available(*, unavailable, renamed:"Signal.Event")
public typealias Event<Value, Error: Swift.Error> = Signal<Value, Error>.Event

@available(*, unavailable, renamed:"Signal.Observer")
public typealias Observer<Value, Error: Swift.Error> = Signal<Value, Error>.Observer

extension Action {
	@available(*, unavailable, renamed:"init(state:enabledIf:execute:)")
	public convenience init<State: PropertyProtocol>(state property: State, enabledIf isEnabled: @escaping (State.Value) -> Bool, _ execute: @escaping (State.Value, Input) -> SignalProducer<Output, Error>) { fatalError() }

	@available(*, unavailable, renamed:"init(enabledIf:execute:)")
	public convenience init<P: PropertyProtocol>(enabledIf property: P, _ execute: @escaping (Input) -> SignalProducer<Output, Error>) where P.Value == Bool { fatalError() }

	@available(*, unavailable, renamed:"init(execute:)")
	public convenience init(_ execute: @escaping (Input) -> SignalProducer<Output, Error>) { fatalError() }
}

extension Action where Input == Void {
	@available(*, unavailable, renamed:"init(unwrapping:execute:)")
	public convenience init<P: PropertyProtocol, T>(state: P, _ execute: @escaping (T) -> SignalProducer<Output, Error>) where P.Value == T? { fatalError() }

	@available(*, unavailable, renamed:"init(unwrapping:execute:)")
	public convenience init<P: PropertyProtocol, T>(input: P, _ execute: @escaping (T) -> SignalProducer<Output, Error>) where P.Value == T? { fatalError() }

	@available(*, unavailable, renamed:"init(state:execute:)")
	public convenience init<P: PropertyProtocol, T>(input: P, _ execute: @escaping (T) -> SignalProducer<Output, Error>) where P.Value == T { fatalError() }
}

@available(*, unavailable, renamed:"Bag.Token")
public typealias RemovalToken = Bag<Any>.Token

@available(*, unavailable, message: "This protocol has been removed. Constrain `Action` directly instead.")
public protocol ActionProtocol {}

@available(*, unavailable, message: "The protocol has been removed. Constrain `Observer` directly instead.")
public protocol ObserverProtocol {}

@available(*, unavailable, message:"The protocol has been replaced by `BindingTargetProvider`.")
public protocol BindingTargetProtocol {}

@available(*, unavailable, message:"The protocol has been removed. Constrain `Atomic` directly instead.")
public protocol AtomicProtocol {}

// MARK: Deprecated types in ReactiveSwift 1.x.
@available(*, unavailable, renamed:"ValidationProperty.Result")
public typealias ValidationResult<Value, Error: Swift.Error> = ValidatingProperty<Value, Error>.Result

@available(*, unavailable, renamed:"ValidationProperty.Decision")
public typealias ValidatorOutput<Value, Error: Swift.Error> = ValidatingProperty<Value, Error>.Decision

extension Signal where Value == Bool {
	@available(*, unavailable, renamed: "negate()")
	public var negated: Signal<Bool, Error> {
		return negate()
	}
}

extension SignalProducer where Value == Bool {
	@available(*, unavailable, renamed: "negate()")
	public var negated: SignalProducer<Bool, Error> {
		return negate()
	}
}

extension PropertyProtocol where Value == Bool {
	@available(*, unavailable, renamed: "negate()")
	public var negated: Property<Bool> {
		return negate()
	}
}

@available(*, unavailable, renamed:"Scheduler")
public typealias SchedulerProtocol = Scheduler

@available(*, unavailable, renamed:"DateScheduler")
public typealias DateSchedulerProtocol = DateScheduler

@available(*, unavailable, renamed:"BindingSource")
public typealias BindingSourceProtocol = BindingSource
