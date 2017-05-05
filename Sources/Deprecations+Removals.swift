import Foundation
import Dispatch
import enum Result.NoError

// MARK: Unavailable methods in ReactiveSwift 2.0.
extension PropertyProtocol {
	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<P: PropertyProtocol>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> P) -> Property<P.Value> { fatalError() }
}

extension Signal {
	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<U>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> SignalProducer<U, Error>) -> Signal<U, Error> { fatalError() }

	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<U>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> SignalProducer<U, NoError>) -> Signal<U, Error> { fatalError() }

	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<U>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> Signal<U, Error>) -> Signal<U, Error> { fatalError() }

	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<U>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> Signal<U, NoError>) -> Signal<U, Error> { fatalError() }

	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<P: PropertyProtocol>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> P) -> Signal<P.Value, Error> { fatalError() }
}

extension Signal where Error == NoError {
	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<U, E>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> SignalProducer<U, E>) -> Signal<U, E> { fatalError() }

	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<U>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> SignalProducer<U, NoError>) -> Signal<U, NoError> { fatalError() }

	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<U, E>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> Signal<U, E>) -> Signal<U, E> { fatalError() }

	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<U>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> Signal<U, NoError>) -> Signal<U, NoError> { fatalError() }
}

extension SignalProducer {
	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<U>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> SignalProducer<U, Error>) -> SignalProducer<U, Error> { fatalError() }

	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<U>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> SignalProducer<U, NoError>) -> SignalProducer<U, Error> { fatalError() }

	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<U>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> Signal<U, Error>) -> SignalProducer<U, Error> { fatalError() }

	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<U>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> Signal<U, NoError>) -> SignalProducer<U, Error> { fatalError() }

	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<P: PropertyProtocol>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> P) -> SignalProducer<P.Value, Error> { fatalError() }
}

extension SignalProducer where Error == NoError {
	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<U, E>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> SignalProducer<U, E>) -> SignalProducer<U, E> { fatalError() }

	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<U>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> SignalProducer<U, NoError>) -> SignalProducer<U, NoError> { fatalError() }

	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<U, E>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> Signal<U, E>) -> SignalProducer<U, E> { fatalError() }

	@available(*, unavailable, renamed:"flatMap(_:_:)")
	public func flatMap<U>(_ strategy: FlattenStrategy, transform: @escaping (Value) -> Signal<U, NoError>) -> SignalProducer<U, NoError> { fatalError() }
}

extension ComposableMutablePropertyProtocol {
	@available(*, unavailable, renamed:"withValue(_:)")
	public func withValue<Result>(action: (Value) throws -> Result) rethrows -> Result { fatalError() }
}

@available(*, unavailable, renamed:"SignalProducer.timer")
public func timer(interval: DispatchTimeInterval, on scheduler: DateScheduler) -> SignalProducer<Date, NoError> { fatalError() }

@available(*, unavailable, renamed:"SignalProducer.timer")
public func timer(interval: DispatchTimeInterval, on scheduler: DateScheduler, leeway: DispatchTimeInterval) -> SignalProducer<Date, NoError> { fatalError() }

// MARK: Obsolete types in ReactiveSwift 2.0.
extension Action {
	@available(*, unavailable, renamed:"init(state:enabledIf:execute:)")
	public convenience init<State: PropertyProtocol>(state property: State, enabledIf isEnabled: @escaping (State.Value) -> Bool, _ execute: @escaping (State.Value, Input) -> SignalProducer<Output, Error>) { fatalError() }

	@available(*, unavailable, renamed:"init(enabledIf:execute:)")
	public convenience init<P: PropertyProtocol>(enabledIf property: P, _ execute: @escaping (Input) -> SignalProducer<Output, Error>) where P.Value == Bool { fatalError() }

	@available(*, unavailable, renamed:"init(execute:)")
	public convenience init(_ execute: @escaping (Input) -> SignalProducer<Output, Error>) { fatalError() }
}

extension Action where Input == Void {
	@available(*, unavailable, renamed:"init(state:execute:)")
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

// MARK: Depreciated types in ReactiveSwift 1.x.
extension Signal where Value == Bool {
	@available(*, deprecated, renamed: "negate()")
	public var negated: Signal<Bool, Error> {
		return negate()
	}
}

extension SignalProducer where Value == Bool {
	@available(*, deprecated, renamed: "negate()")
	public var negated: SignalProducer<Bool, Error> {
		return negate()
	}
}

extension PropertyProtocol where Value == Bool {
	@available(*, deprecated, renamed: "negate()")
	public var negated: Property<Bool> {
		return negate()
	}
}

@available(*, deprecated, renamed:"Scheduler")
public typealias SchedulerProtocol = Scheduler

@available(*, deprecated, renamed:"DateScheduler")
public typealias DateSchedulerProtocol = DateScheduler

@available(*, deprecated, renamed:"BindingSource")
public typealias BindingSourceProtocol = BindingSource

// MARK: Removed Types and APIs in ReactiveCocoa 5.0.

// Renamed Protocols
@available(*, unavailable, renamed:"ActionProtocol")
public enum ActionType {}

@available(*, unavailable, renamed:"SignalProtocol")
public enum SignalType {}

@available(*, unavailable, renamed:"SignalProducerProtocol")
public enum SignalProducerType {}

@available(*, unavailable, renamed:"PropertyProtocol")
public enum PropertyType {}

@available(*, unavailable, renamed:"MutablePropertyProtocol")
public enum MutablePropertyType {}

@available(*, unavailable, renamed:"ObserverProtocol")
public enum ObserverType {}

@available(*, unavailable, renamed:"Scheduler")
public enum SchedulerType {}

@available(*, unavailable, renamed:"DateScheduler")
public enum DateSchedulerType {}

@available(*, unavailable, renamed:"OptionalProtocol")
public enum OptionalType {}

@available(*, unavailable, renamed:"EventLoggerProtocol")
public enum EventLoggerType {}

@available(*, unavailable, renamed:"EventProtocol")
public enum EventType {}

// Renamed and Removed Types

@available(*, unavailable, renamed:"Property")
public struct AnyProperty<Value> {}

@available(*, unavailable, message:"Use 'Property(value:)' to create a constant property instead. 'ConstantProperty' is removed in RAC 5.0.")
public struct ConstantProperty<Value> {}

// Renamed Properties

extension Disposable {
	@available(*, unavailable, renamed:"isDisposed")
	public var disposed: Bool { fatalError() }
}

extension SerialDisposable {
	@available(*, unavailable, renamed:"inner")
	public var innerDisposable: Disposable? {
		get { fatalError() }
		set { fatalError() }
 }
}

extension ScopedDisposable {
	@available(*, unavailable, renamed:"inner")
	public var innerDisposable: Disposable { fatalError() }
}

extension Action {
	@available(*, unavailable, renamed:"isEnabled")
	public var enabled: Bool { fatalError() }

	@available(*, unavailable, renamed:"isExecuting")
	public var executing: Bool { fatalError() }
}

// Renamed Enum cases

extension Event {
	@available(*, unavailable, renamed:"value")
	public static var Next: Event<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"failed")
	public static var Failed: Event<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"completed")
	public static var Completed: Event<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"interrupted")
	public static var Interrupted: Event<Value, Error> { fatalError() }
}

extension ActionError {
	@available(*, unavailable, renamed:"producerFailed")
	public static var ProducerError: ActionError { fatalError() }

	@available(*, unavailable, renamed:"disabled")
	public static var NotEnabled: ActionError { fatalError() }
}

extension FlattenStrategy {
	@available(*, unavailable, renamed:"latest")
	public static var Latest: FlattenStrategy { fatalError() }

	@available(*, unavailable, renamed:"concat")
	public static var Concat: FlattenStrategy { fatalError() }

	@available(*, unavailable, renamed:"merge")
	public static var Merge: FlattenStrategy { fatalError() }
}

extension LoggingEvent.Signal {
	@available(*, unavailable, renamed:"next")
	public static var Next: LoggingEvent.Signal { fatalError() }

	@available(*, unavailable, renamed:"completed")
	public static var Completed: LoggingEvent.Signal { fatalError() }

	@available(*, unavailable, renamed:"failed")
	public static var Failed: LoggingEvent.Signal { fatalError() }

	@available(*, unavailable, renamed:"terminated")
	public static var Terminated: LoggingEvent.Signal { fatalError() }

	@available(*, unavailable, renamed:"disposed")
	public static var Disposed: LoggingEvent.Signal { fatalError() }

	@available(*, unavailable, renamed:"interrupted")
	public static var Interrupted: LoggingEvent.Signal { fatalError() }
}

extension LoggingEvent.SignalProducer {
	@available(*, unavailable, renamed:"started")
	public static var Started: LoggingEvent.Signal { fatalError() }

	@available(*, unavailable, renamed:"next")
	public static var Next: LoggingEvent.Signal { fatalError() }

	@available(*, unavailable, renamed:"completed")
	public static var Completed: LoggingEvent.Signal { fatalError() }

	@available(*, unavailable, renamed:"failed")
	public static var Failed: LoggingEvent.Signal { fatalError() }

	@available(*, unavailable, renamed:"terminated")
	public static var Terminated: LoggingEvent.Signal { fatalError() }

	@available(*, unavailable, renamed:"disposed")
	public static var Disposed: LoggingEvent.Signal { fatalError() }

	@available(*, unavailable, renamed:"interrupted")
	public static var Interrupted: LoggingEvent.Signal { fatalError() }
}

// Methods

extension Bag {
	@available(*, unavailable, renamed:"remove(using:)")
	public func removeValueForToken(_ token: Token) { fatalError() }
}

extension CompositeDisposable {
	@available(*, unavailable, renamed:"add(_:)")
	public func addDisposable(_ d: Disposable) -> DisposableHandle { fatalError() }
}

extension Observer {
	@available(*, unavailable, renamed: "init(value:failed:completed:interrupted:)")
	public convenience init(
		next: ((Value) -> Void)? = nil,
		failed: ((Error) -> Void)? = nil,
		completed: (() -> Void)? = nil,
		interrupted: (() -> Void)? = nil
		) { fatalError() }

	@available(*, unavailable, renamed: "send(value:)")
	public func sendNext(_ value: Value) { fatalError() }
	
	@available(*, unavailable, renamed: "send(error:)")
	public func sendFailed(_ error: Error) { fatalError() }
}

extension Signal {
	@available(*, unavailable, renamed:"take(first:)")
	public func take(_ count: Int) -> Signal<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"take(last:)")
	public func takeLast(_ count: Int) -> Signal<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"skip(first:)")
	public func skip(_ count: Int) -> Signal<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"observe(on:)")
	public func observeOn(_ scheduler: Scheduler) -> Signal<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"combineLatest(with:)")
	public func combineLatestWith<S: SignalProtocol>(_ otherSignal: S) -> Signal<(Value, S.Value), Error> { fatalError() }

	@available(*, unavailable, renamed:"zip(with:)")
	public func zipWith<S: SignalProtocol>(_ otherSignal: S) -> Signal<(Value, S.Value), Error> { fatalError() }

	@available(*, unavailable, renamed:"take(until:)")
	public func takeUntil(_ trigger: Signal<(), NoError>) -> Signal<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"take(untilReplacement:)")
	public func takeUntilReplacement(_ replacement: Signal<Value, Error>) -> Signal<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"skip(until:)")
	public func skipUntil(_ trigger: Signal<(), NoError>) -> Signal<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"skip(while:)")
	public func skipWhile(_ predicate: (Value) -> Bool) -> Signal<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"take(while:)")
	public func takeWhile(_ predicate: (Value) -> Bool) -> Signal<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"timeout(after:raising:on:)")
	public func timeoutWithError(_ error: Error, afterInterval: TimeInterval, onScheduler: DateScheduler) -> Signal<Value, Error> { fatalError() }

	@available(*, unavailable, message: "This Signal may emit errors which must be handled explicitly, or observed using `observeResult(_:)`")
	public func observeNext(_ next: (Value) -> Void) -> Disposable? { fatalError() }
}

extension Signal where Value: OptionalProtocol {
	@available(*, unavailable, renamed:"skipNil()")
	public func ignoreNil() -> SignalProducer<Value.Wrapped, Error> { fatalError() }
}

extension Signal where Error == NoError {
	@available(*, unavailable, renamed: "observeValues")
	public func observeNext(_ next: (Value) -> Void) -> Disposable? { fatalError() }
}

extension Signal where Value: Sequence {
	@available(*, deprecated, message: "Use flatten() instead")
	public func flatten(_ strategy: FlattenStrategy) -> Signal<Value.Iterator.Element, Error> {
		return self.flatMap(strategy, SignalProducer.init)
	}
}

extension SignalProducer {
	@available(*, unavailable, renamed:"take(first:)")
	public func take(_ count: Int) -> SignalProducer<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"take(last:)")
	public func takeLast(_ count: Int) -> SignalProducer<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"skip(first:)")
	public func skip(_ count: Int) -> SignalProducer<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"retry(upTo:)")
	public func retry(_ count: Int) -> SignalProducer<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"observe(on:)")
	public func observeOn(_ scheduler: Scheduler) -> SignalProducer<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"start(on:)")
	public func startOn(_ scheduler: Scheduler) -> SignalProducer<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"combineLatest(with:)")
	public func combineLatestWith<U>(_ otherProducer: SignalProducer<U, Error>) -> SignalProducer<(Value, U), Error> { fatalError() }

	@available(*, unavailable, renamed:"combineLatest(with:)")
	public func combineLatestWith<U>(_ otherSignal: Signal<U, Error>) -> SignalProducer<(Value, U), Error> { fatalError() }

	@available(*, unavailable, renamed:"zip(with:)")
	public func zipWith<U>(_ otherProducer: SignalProducer<U, Error>) -> SignalProducer<(Value, U), Error> { fatalError() }

	@available(*, unavailable, renamed:"zip(with:)")
	public func zipWith<U>(_ otherSignal: Signal<U, Error>) -> SignalProducer<(Value, U), Error> { fatalError() }

	@available(*, unavailable, renamed:"take(until:)")
	public func takeUntil(_ trigger: Signal<(), NoError>) -> SignalProducer<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"take(until:)")
	public func takeUntil(_ trigger: SignalProducer<(), NoError>) -> SignalProducer<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"take(untilReplacement:)")
	public func takeUntilReplacement(_ replacement: Signal<Value, Error>) -> SignalProducer<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"take(untilReplacement:)")
	public func takeUntilReplacement(_ replacement: SignalProducer<Value, Error>) -> SignalProducer<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"skip(until:)")
	public func skipUntil(_ trigger: Signal<(), NoError>) -> SignalProducer<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"skip(until:)")
	public func skipUntil(_ trigger: SignalProducer<(), NoError>) -> SignalProducer<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"skip(while:)")
	public func skipWhile(_ predicate: (Value) -> Bool) -> SignalProducer<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"take(while:)")
	public func takeWhile(_ predicate: (Value) -> Bool) -> SignalProducer<Value, Error> { fatalError() }

	@available(*, unavailable, renamed:"timeout(after:raising:on:)")
	public func timeoutWithError(_ error: Error, afterInterval: TimeInterval, onScheduler: DateScheduler) -> SignalProducer<Value, Error> { fatalError() }

	@available(*, unavailable, message:"This SignalProducer may emit errors which must be handled explicitly, or observed using `startWithResult(_:)`.")
	public func startWithNext(_ next: (Value) -> Void) -> Disposable { fatalError() }

	@available(*, unavailable, renamed:"repeat(_:)")
	public func times(_ count: Int) -> SignalProducer<Value, Error> { fatalError() }
}

extension SignalProducer where Value: OptionalProtocol {
	@available(*, unavailable, renamed:"skipNil()")
	public func ignoreNil() -> SignalProducer<Value.Wrapped, Error> { fatalError() }
}

extension SignalProducer where Error == NoError {
	@available(*, unavailable, renamed: "startWithValues")
	public func startWithNext(_ value: @escaping (Value) -> Void) -> Disposable { fatalError() }
}

extension SignalProducer where Value: Sequence {
	@available(*, deprecated, message: "Use flatten() instead")
	public func flatten(_ strategy: FlattenStrategy) -> SignalProducer<Value.Iterator.Element, Error> {
		return self.flatMap(strategy, SignalProducer<Value.Iterator.Element, NoError>.init)
	}
}

extension SignalProducer {
	@available(*, unavailable, message:"Use properties instead. `buffer(_:)` is removed in RAC 5.0.")
	public static func buffer(_ capacity: Int) -> (SignalProducer, Signal<Value, Error>.Observer) { fatalError() }

	@available(*, unavailable, renamed:"init(_:)")
	public init<S: SignalProtocol>(signal: S) where S.Value == Value, S.Error == Error { fatalError() }

	@available(*, unavailable, renamed:"init(_:)")
	public init<S: Sequence>(values: S) where S.Iterator.Element == Value { fatalError() }
}

extension PropertyProtocol {
	@available(*, unavailable, renamed:"combineLatest(with:)")
	public func combineLatestWith<P: PropertyProtocol>(_ otherProperty: P) -> Property<(Value, P.Value)> { fatalError() }

	@available(*, unavailable, renamed:"zip(with:)")
	public func zipWith<P: PropertyProtocol>(_ otherProperty: P) -> Property<(Value, P.Value)> { fatalError() }
}

extension Property {
	@available(*, unavailable, renamed:"Property(initial:then:)")
	public convenience init(initialValue: Value, producer: SignalProducer<Value, NoError>) { fatalError() }

	@available(*, unavailable, renamed:"Property(initial:then:)")
	public convenience init(initialValue: Value, signal: Signal<Value, NoError>) { fatalError() }
}

extension DateScheduler {
	@available(*, unavailable, renamed:"schedule(after:action:)")
	func scheduleAfter(date: Date, _ action: () -> Void) -> Disposable? { fatalError() }

	@available(*, unavailable, renamed:"schedule(after:interval:leeway:)")
	func scheduleAfter(date: Date, repeatingEvery: TimeInterval, withLeeway: TimeInterval, action: () -> Void) -> Disposable? { fatalError() }

	@available(*, unavailable, message:"schedule(after:interval:leeway:action:) now uses DispatchTimeInterval")
	func schedule(after date: Date, interval: TimeInterval, leeway: TimeInterval, action: @escaping () -> Void) -> Disposable? { fatalError() }

	@available(*, unavailable, message:"schedule(after:interval:action:) now uses DispatchTimeInterval")
	public func schedule(after date: Date, interval: TimeInterval, action: @escaping () -> Void) -> Disposable? { fatalError() }
}

extension TestScheduler {
	@available(*, unavailable, renamed:"advance(by:)")
	public func advanceByInterval(_ interval: TimeInterval) { fatalError() }

	@available(*, unavailable, renamed:"advance(to:)")
	public func advanceToDate(_ date: Date) { fatalError() }

	@available(*, unavailable, message:"advance(by:) now uses DispatchTimeInterval")
	public func advance(by interval: TimeInterval) { fatalError() }

	@available(*, unavailable, message:"rewind(by:) now uses DispatchTimeInterval")
	public func rewind(by interval: TimeInterval) { fatalError() }
}

extension QueueScheduler {
	@available(*, unavailable, renamed:"main")
	public static var mainQueueScheduler: QueueScheduler { fatalError() }
}

extension NotificationCenter {
	@available(*, unavailable, renamed:"reactive.notifications")
	public func rac_notifications(forName name: Notification.Name?, object: AnyObject? = nil) -> SignalProducer<Notification, NoError> { fatalError() }
}

extension URLSession {
	@available(*, unavailable, renamed:"reactive.data")
	public func rac_data(with request: URLRequest) -> SignalProducer<(Data, URLResponse), NSError> { fatalError() }
}

extension Reactive where Base: URLSession {
	@available(*, unavailable, message:"Use the overload which returns `SignalProducer<(Data, URLResponse), AnyError>` instead, and cast `AnyError.error` to `NSError` as you need")
	public func data(with request: URLRequest) -> SignalProducer<(Data, URLResponse), NSError> { fatalError() }
}

// Free functions

@available(*, unavailable, message:"timer(interval:on:) now uses DispatchTimeInterval")
public func timer(interval: TimeInterval, on scheduler: DateScheduler) -> SignalProducer<Date, NoError> { fatalError() }

@available(*, unavailable, message:"timer(interval:on:leeway:) now uses DispatchTimeInterval")
public func timer(interval: TimeInterval, on scheduler: DateScheduler, leeway: TimeInterval) -> SignalProducer<Date, NoError> { fatalError() }

@available(*, unavailable, renamed:"Signal.combineLatest")
public func combineLatest<A, B, Error>(_ a: Signal<A, Error>, _ b: Signal<B, Error>) -> Signal<(A, B), Error> { fatalError() }

@available(*, unavailable, renamed:"Signal.combineLatest")
public func combineLatest<A, B, C, Error>(_ a: Signal<A, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>) -> Signal<(A, B, C), Error> { fatalError() }

@available(*, unavailable, renamed:"Signal.combineLatest")
public func combineLatest<A, B, C, D, Error>(_ a: Signal<A, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>) -> Signal<(A, B, C, D), Error> { fatalError() }

@available(*, unavailable, renamed:"Signal.combineLatest")
public func combineLatest<A, B, C, D, E, Error>(_ a: Signal<A, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>) -> Signal<(A, B, C, D, E), Error> { fatalError() }

@available(*, unavailable, renamed:"Signal.combineLatest")
public func combineLatest<A, B, C, D, E, F, Error>(_ a: Signal<A, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>) -> Signal<(A, B, C, D, E, F), Error> { fatalError() }

@available(*, unavailable, renamed:"Signal.combineLatest")
public func combineLatest<A, B, C, D, E, F, G, Error>(_ a: Signal<A, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>) -> Signal<(A, B, C, D, E, F, G), Error> { fatalError() }

@available(*, unavailable, renamed:"Signal.combineLatest")
public func combineLatest<A, B, C, D, E, F, G, H, Error>(_ a: Signal<A, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>, _ h: Signal<H, Error>) -> Signal<(A, B, C, D, E, F, G, H), Error> { fatalError() }

@available(*, unavailable, renamed:"Signal.combineLatest")
public func combineLatest<A, B, C, D, E, F, G, H, I, Error>(_ a: Signal<A, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>, _ h: Signal<H, Error>, _ i: Signal<I, Error>) -> Signal<(A, B, C, D, E, F, G, H, I), Error> { fatalError() }

@available(*, unavailable, renamed:"Signal.combineLatest")
public func combineLatest<A, B, C, D, E, F, G, H, I, J, Error>(_ a: Signal<A, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>, _ h: Signal<H, Error>, _ i: Signal<I, Error>, _ j: Signal<J, Error>) -> Signal<(A, B, C, D, E, F, G, H, I, J), Error> { fatalError() }

@available(*, unavailable, renamed:"Signal.combineLatest")
public func combineLatest<S: Sequence, Value, Error>(_ signals: S) -> Signal<[Value], Error> where S.Iterator.Element == Signal<Value, Error> { fatalError() }

@available(*, unavailable, renamed:"Signal.zip")
public func zip<A, B, Error>(_ a: Signal<A, Error>, _ b: Signal<B, Error>) -> Signal<(A, B), Error> { fatalError() }

@available(*, unavailable, renamed:"Signal.zip")
public func zip<A, B, C, Error>(_ a: Signal<A, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>) -> Signal<(A, B, C), Error> { fatalError() }

@available(*, unavailable, renamed:"Signal.zip")
public func zip<A, B, C, D, Error>(_ a: Signal<A, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>) -> Signal<(A, B, C, D), Error> { fatalError() }

@available(*, unavailable, renamed:"Signal.zip")
public func zip<A, B, C, D, E, Error>(_ a: Signal<A, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>) -> Signal<(A, B, C, D, E), Error> { fatalError() }

@available(*, unavailable, renamed:"Signal.zip")
public func zip<A, B, C, D, E, F, Error>(_ a: Signal<A, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>) -> Signal<(A, B, C, D, E, F), Error> { fatalError() }

@available(*, unavailable, renamed:"Signal.zip")
public func zip<A, B, C, D, E, F, G, Error>(_ a: Signal<A, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>) -> Signal<(A, B, C, D, E, F, G), Error> { fatalError() }

@available(*, unavailable, renamed:"Signal.zip")
public func zip<A, B, C, D, E, F, G, H, Error>(_ a: Signal<A, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>, _ h: Signal<H, Error>) -> Signal<(A, B, C, D, E, F, G, H), Error> { fatalError() }

@available(*, unavailable, renamed:"Signal.zip")
public func zip<A, B, C, D, E, F, G, H, I, Error>(_ a: Signal<A, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>, _ h: Signal<H, Error>, _ i: Signal<I, Error>) -> Signal<(A, B, C, D, E, F, G, H, I), Error> { fatalError() }

@available(*, unavailable, renamed:"Signal.zip")
public func zip<A, B, C, D, E, F, G, H, I, J, Error>(_ a: Signal<A, Error>, _ b: Signal<B, Error>, _ c: Signal<C, Error>, _ d: Signal<D, Error>, _ e: Signal<E, Error>, _ f: Signal<F, Error>, _ g: Signal<G, Error>, _ h: Signal<H, Error>, _ i: Signal<I, Error>, _ j: Signal<J, Error>) -> Signal<(A, B, C, D, E, F, G, H, I, J), Error> { fatalError() }

@available(*, unavailable, renamed:"Signal.zip")
public func zip<S: Sequence, Value, Error>(_ signals: S) -> Signal<[Value], Error> where S.Iterator.Element == Signal<Value, Error> { fatalError() }

@available(*, unavailable, renamed:"SignalProducer.combineLatest")
public func combineLatest<A, B, Error>(_ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>) -> SignalProducer<(A, B), Error> { fatalError() }

@available(*, unavailable, renamed:"SignalProducer.combineLatest")
public func combineLatest<A, B, C, Error>(_ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>) -> SignalProducer<(A, B, C), Error> { fatalError() }

@available(*, unavailable, renamed:"SignalProducer.combineLatest")
public func combineLatest<A, B, C, D, Error>(_ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>) -> SignalProducer<(A, B, C, D), Error> { fatalError() }

@available(*, unavailable, renamed:"SignalProducer.combineLatest")
public func combineLatest<A, B, C, D, E, Error>(_ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>) -> SignalProducer<(A, B, C, D, E), Error> { fatalError() }

@available(*, unavailable, renamed:"SignalProducer.combineLatest")
public func combineLatest<A, B, C, D, E, F, Error>(_ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>) -> SignalProducer<(A, B, C, D, E, F), Error> { fatalError() }

@available(*, unavailable, renamed:"SignalProducer.combineLatest")
public func combineLatest<A, B, C, D, E, F, G, Error>(_ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>) -> SignalProducer<(A, B, C, D, E, F, G), Error> { fatalError() }

@available(*, unavailable, renamed:"SignalProducer.combineLatest")
public func combineLatest<A, B, C, D, E, F, G, H, Error>(_ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>, _ h: SignalProducer<H, Error>) -> SignalProducer<(A, B, C, D, E, F, G, H), Error> { fatalError() }

@available(*, unavailable, renamed:"SignalProducer.combineLatest")
public func combineLatest<A, B, C, D, E, F, G, H, I, Error>(_ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>, _ h: SignalProducer<H, Error>, _ i: SignalProducer<I, Error>) -> SignalProducer<(A, B, C, D, E, F, G, H, I), Error> { fatalError() }

@available(*, unavailable, renamed:"SignalProducer.combineLatest")
public func combineLatest<A, B, C, D, E, F, G, H, I, J, Error>(_ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>, _ h: SignalProducer<H, Error>, _ i: SignalProducer<I, Error>, _ j: SignalProducer<J, Error>) -> SignalProducer<(A, B, C, D, E, F, G, H, I, J), Error> { fatalError() }

@available(*, unavailable, renamed:"SignalProducer.combineLatest")
public func combineLatest<S: Sequence, Value, Error>(_ producers: S) -> SignalProducer<[Value], Error> where S.Iterator.Element == SignalProducer<Value, Error> { fatalError() }

@available(*, unavailable, renamed:"SignalProducer.zip")
public func zip<A, B, Error>(_ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>) -> SignalProducer<(A, B), Error> { fatalError() }

@available(*, unavailable, renamed:"SignalProducer.zip")
public func zip<A, B, C, Error>(_ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>) -> SignalProducer<(A, B, C), Error> { fatalError() }

@available(*, unavailable, renamed:"SignalProducer.zip")
public func zip<A, B, C, D, Error>(_ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>) -> SignalProducer<(A, B, C, D), Error> { fatalError() }

@available(*, unavailable, renamed:"SignalProducer.zip")
public func zip<A, B, C, D, E, Error>(_ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>) -> SignalProducer<(A, B, C, D, E), Error> { fatalError() }

@available(*, unavailable, renamed:"SignalProducer.zip")
public func zip<A, B, C, D, E, F, Error>(_ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>) -> SignalProducer<(A, B, C, D, E, F), Error> { fatalError() }

@available(*, unavailable, renamed:"SignalProducer.zip")
public func zip<A, B, C, D, E, F, G, Error>(_ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>) -> SignalProducer<(A, B, C, D, E, F, G), Error> {
	fatalError()}

@available(*, unavailable, renamed:"SignalProducer.zip")
public func zip<A, B, C, D, E, F, G, H, Error>(_ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>, _ h: SignalProducer<H, Error>) -> SignalProducer<(A, B, C, D, E, F, G, H), Error> { fatalError() }

@available(*, unavailable, renamed:"SignalProducer.zip")
public func zip<A, B, C, D, E, F, G, H, I, Error>(_ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>, _ h: SignalProducer<H, Error>, _ i: SignalProducer<I, Error>) -> SignalProducer<(A, B, C, D, E, F, G, H, I), Error> { fatalError() }

@available(*, unavailable, renamed:"SignalProducer.zip")
public func zip<A, B, C, D, E, F, G, H, I, J, Error>(_ a: SignalProducer<A, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>, _ d: SignalProducer<D, Error>, _ e: SignalProducer<E, Error>, _ f: SignalProducer<F, Error>, _ g: SignalProducer<G, Error>, _ h: SignalProducer<H, Error>, _ i: SignalProducer<I, Error>, _ j: SignalProducer<J, Error>) -> SignalProducer<(A, B, C, D, E, F, G, H, I, J), Error> { fatalError() }

@available(*, unavailable, renamed:"SignalProducer.zip")
public func zip<S: Sequence, Value, Error>(_ producers: S) -> SignalProducer<[Value], Error> where S.Iterator.Element == SignalProducer<Value, Error> { fatalError() }
