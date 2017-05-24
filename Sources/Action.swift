import Dispatch
import Foundation
import Result

/// `Action` represents a repeatable work like `SignalProducer`. But on top of the
/// isolation of produced `Signal`s from a `SignalProducer`, `Action` provides
/// higher-order features like availability and mutual exclusion.
///
/// Similar to a produced `Signal` from a `SignalProducer`, each unit of the repreatable
/// work may output zero or more values, and terminate with or without an error at some
/// point.
///
/// The core of `Action` is the `execute` closure it created with. For every execution
/// attempt with a varying input, if the `Action` is enabled, it would request from the
/// `execute` closure a customized unit of work — represented by a `SignalProducer`.
/// Specifically, the `execute` closure would be supplied with the latest state of
/// `Action` and the external input from `apply()`.
///
/// `Action` enforces serial execution, and disables the `Action` during the execution.
public final class Action<Input, Output, Error: Swift.Error> {
	private let deinitToken: Lifetime.Token

	private let executeClosure: (_ state: Any, _ input: Input) -> SignalProducer<Output, Error>
	private let eventsObserver: Signal<Signal<Output, Error>.Event, NoError>.Observer
	private let disabledErrorsObserver: Signal<(), NoError>.Observer

	/// The lifetime of the `Action`.
	public let lifetime: Lifetime

	/// A signal of all events generated from all units of work of the `Action`.
	///
	/// In other words, this sends every `Event` from every unit of work that the `Action`
	/// executes.
	public let events: Signal<Signal<Output, Error>.Event, NoError>

	/// A signal of all values generated from all units of work of the `Action`.
	///
	/// In other words, this sends every value from every unit of work that the `Action`
	/// executes.
	public let values: Signal<Output, NoError>

	/// A signal of all errors generated from all units of work of the `Action`.
	///
	/// In other words, this sends every error from every unit of work that the `Action`
	/// executes.
	public let errors: Signal<Error, NoError>

	/// A signal of all failed attempts to start a unit of work of the `Action`.
	public let disabledErrors: Signal<(), NoError>

	/// A signal of all completed events generated from applications of the action.
	///
	/// In other words, this will send completed events from every signal generated
	/// by each SignalProducer returned from apply().
	public let completed: Signal<(), NoError>

	/// Whether the action is currently executing.
	public let isExecuting: Property<Bool>

	/// Whether the action is currently enabled.
	public let isEnabled: Property<Bool>

	private let state: MutableProperty<ActionState>

	/// Initializes an `Action` that would be conditionally enabled depending on its
	/// state.
	///
	/// When the `Action` is asked to start the execution with an input value, a unit of
	/// work — represented by a `SignalProducer` — would be created by invoking
	/// `execute` with the latest state and the input value.
	///
	/// - note: `Action` guarantees that changes to `state` are observed in a
	///         thread-safe way. Thus, the value passed to `isEnabled` will
	///         always be identical to the value passed to `execute`, for each
	///         application of the action.
	///
	/// - note: This initializer should only be used if you need to provide
	///         custom input can also influence whether the action is enabled.
	///         The various convenience initializers should cover most use cases.
	///
	/// - parameters:
	///   - state: A property to be the state of the `Action`.
	///   - enabledIf: A predicate which determines the availability of the `Action`,
	///                given the latest `Action` state.
	///   - execute: A closure that produces a unit of work, as `SignalProducer`, to be
	///              executed by the `Action`.
	public init<State: PropertyProtocol>(state property: State, enabledIf isEnabled: @escaping (State.Value) -> Bool, execute: @escaping (State.Value, Input) -> SignalProducer<Output, Error>) {
		deinitToken = Lifetime.Token()
		lifetime = Lifetime(deinitToken)
		
		// Retain the `property` for the created `Action`.
		lifetime.observeEnded { _ = property }

		executeClosure = { state, input in execute(state as! State.Value, input) }

		(events, eventsObserver) = Signal<Signal<Output, Error>.Event, NoError>.pipe()
		(disabledErrors, disabledErrorsObserver) = Signal<(), NoError>.pipe()

		values = events.filterMap { $0.value }
		errors = events.filterMap { $0.error }
		completed = events.filter { $0.isCompleted }.map { _ in }

		let initial = ActionState(value: property.value, isEnabled: { isEnabled($0 as! State.Value) })
		state = MutableProperty(initial)

		property.signal
			.take(during: state.lifetime)
			.observeValues { [weak state] newValue in
				state?.modify {
					$0.value = newValue
				}
			}

		self.isEnabled = state.map { $0.isEnabled }.skipRepeats()
		self.isExecuting = state.map { $0.isExecuting }.skipRepeats()
	}

	/// Initializes an `Action` that would be conditionally enabled.
	///
	/// When the `Action` is asked to start the execution with an input value, a unit of
	/// work — represented by a `SignalProducer` — would be created by invoking
	/// `execute` with the input value.
	///
	/// - parameters:
	///   - enabledIf: A property which determines the availability of the `Action`.
	///   - execute: A closure that produces a unit of work, as `SignalProducer`, to be
	///              executed by the `Action`.
	public convenience init<P: PropertyProtocol>(enabledIf property: P, execute: @escaping (Input) -> SignalProducer<Output, Error>) where P.Value == Bool {
		self.init(state: property, enabledIf: { $0 }) { _, input in
			execute(input)
		}
	}

	public convenience init<P: PropertyProtocol>(enabledIf isEnabled: P, wrapping inner: Action<Input, Output, Error>) where P.Value == Bool {
		let bothEnabled = isEnabled.and(inner.isEnabled)
		self.init(state: bothEnabled, enabledIf: { $0 }, execute: inner.executeClosure)
	}

	/// Initializes an `Action` that would always be enabled.
	///
	/// When the `Action` is asked to start the execution with an input value, a unit of
	/// work — represented by a `SignalProducer` — would be created by invoking
	/// `execute` with the input value.
	///
	/// - parameters:
	///   - execute: A closure that produces a unit of work, as `SignalProducer`, to be
	///              executed by the `Action`.
	public convenience init(execute: @escaping (Input) -> SignalProducer<Output, Error>) {
		self.init(enabledIf: Property(value: true), execute: execute)
	}

	deinit {
		eventsObserver.sendCompleted()
		disabledErrorsObserver.sendCompleted()
	}

	/// Create a `SignalProducer` that would attempt to create and start a unit of work of
	/// the `Action`. The `SignalProducer` would forward only events generated by the unit
	/// of work it created.
	///
	/// If the execution attempt is failed, the producer would fail with
	/// `ActionError.disabled`.
	///
	/// - parameters:
	///   - input: A value to be used to create the unit of work.
	///
	/// - returns: A producer that forwards events generated by its started unit of work,
	///            or emits `ActionError.disabled` if the execution attempt is failed.
	public func apply(_ input: Input) -> SignalProducer<Output, ActionError<Error>> {
		return SignalProducer { observer, lifetime in
			let startingState = self.state.modify { state -> Any? in
				if state.isEnabled {
					state.isExecuting = true
					return state.value
				} else {
					return nil
				}
			}

			guard let state = startingState else {
				observer.send(error: .disabled)
				self.disabledErrorsObserver.send(value: ())
				return
			}

			self.executeClosure(state, input).startWithSignal { signal, signalDisposable in
				lifetime.observeEnded(signalDisposable.dispose)

				signal.observe { event in
					observer.action(event.mapError(ActionError.producerFailed))
					self.eventsObserver.send(value: event)
				}
			}

			lifetime.observeEnded {
				self.state.modify {
					$0.isExecuting = false
				}
			}
		}
	}
}

private struct ActionState {
	var isExecuting: Bool = false

	var value: Any {
		didSet {
			userEnabled = userEnabledClosure(value)
		}
	}

	private var userEnabled: Bool
	private let userEnabledClosure: (Any) -> Bool

	init(value: Any, isEnabled: @escaping (Any) -> Bool) {
		self.value = value
		self.userEnabled = isEnabled(value)
		self.userEnabledClosure = isEnabled
	}

	/// Whether the action should be enabled for the given combination of user
	/// enabledness and executing status.
	fileprivate var isEnabled: Bool {
		return userEnabled && !isExecuting
	}
}

extension Action: BindingTargetProvider {
	public var bindingTarget: BindingTarget<Input> {
		return BindingTarget(lifetime: lifetime) { [weak self] in self?.apply($0).start() }
	}
}

extension Action where Input == Void {
	/// Initializes an `Action` that uses a property of optional as its state.
	///
	/// When the `Action` is asked to start the execution, a unit of work — represented by
	/// a `SignalProducer` — would be created by invoking `execute` with the latest value
	/// of the state.
	///
	/// If the property holds a `nil`, the `Action` would be disabled until it is not
	/// `nil`.
	///
	/// - parameters:
	///   - state: A property of optional to be the state of the `Action`.
	///   - execute: A closure that produces a unit of work, as `SignalProducer`, to
	///              be executed by the `Action`.
	public convenience init<P: PropertyProtocol, T>(state: P, execute: @escaping (T) -> SignalProducer<Output, Error>) where P.Value == T? {
		self.init(state: state, enabledIf: { $0 != nil }) { state, _ in
			execute(state!)
		}
	}

	/// Initializes an `Action` that uses a property as its state.
	///
	/// When the `Action` is asked to start the execution, a unit of work — represented by
	/// a `SignalProducer` — would be created by invoking `execute` with the latest value
	/// of the state.
	///
	/// - parameters:
	///   - state: A property to be the state of the `Action`.
	///   - execute: A closure that produces a unit of work, as `SignalProducer`, to
	///              be executed by the `Action`.
	public convenience init<P: PropertyProtocol, T>(state: P, execute: @escaping (T) -> SignalProducer<Output, Error>) where P.Value == T {
		self.init(state: state.map(Optional.some), execute: execute)
	}
}

/// `ActionError` represents the error that could be emitted by a unit of work of a
/// certain `Action`.
public enum ActionError<Error: Swift.Error>: Swift.Error {
	/// The execution attempt was failed, since the `Action` was disabled.
	case disabled

	/// The unit of work emitted an error.
	case producerFailed(Error)
}

extension ActionError where Error: Equatable {
	public static func == (lhs: ActionError<Error>, rhs: ActionError<Error>) -> Bool {
		switch (lhs, rhs) {
		case (.disabled, .disabled):
			return true

		case let (.producerFailed(left), .producerFailed(right)):
			return left == right

		default:
			return false
		}
	}
}
