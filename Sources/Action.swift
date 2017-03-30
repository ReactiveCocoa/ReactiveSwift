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
	private struct ActionState<Value> {
		var isEnabled: Bool {
			return isUserEnabled && executingCount < queueCapacity
		}

		var isUserEnabled: Bool = true
		var executingCount: UInt = 0
		let queueCapacity: UInt
		var value: Value

		init(queueCapacity: UInt, value: Value) {
			self.queueCapacity = queueCapacity
			self.value = value
		}
	}

	public enum ExecutionStrategy {
		/// Only one worker is allowed to be executing at a time. Any further execution
		/// attempt during the execution is rejected with `ActionError.disabled`.
		case exclusive

		/// Only one worker is allowed to be executing at a time. Any further execution
		/// attempt during the execution would succeed immediately, and interrupt the
		/// previous worker (if any).
		case latest

		/// Only one worker is allowed to be executing at a time. Any further execution
		/// attempt during the execution would be queued.
		case concat

		fileprivate var queueCapacity: UInt {
			switch self {
			case .exclusive:
				return 1

			case .concat, .latest:
				return .max
			}
		}

		fileprivate var flattenStrategy: FlattenStrategy {
			switch self {
			case .exclusive, .concat:
				return .concat

			case .latest:
				return .latest
			}
		}
	}

	private enum Execution {
		case disabled
		case enqueued
		case start(SerialDisposable?, SignalProducer<Output, Error>)
		case replay(SignalProducer<Output, Error>)
	}

	private let workDispatcher: Signal<SignalProducer<Never, NoError>, NoError>.Observer
	private let execute: (Action<Input, Output, Error>, Input) -> SignalProducer<Output, ActionError<Error>>

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
	///   - strategy: The execution strategy of the `Action`. See
	///               `Action.ExecutionStrategy` for more information.
	///   - state: A property to be the state of the `Action`.
	///   - isEnabled: A predicate which determines the availability of the `Action`,
	///                given the latest `Action` state.
	///   - execute: A closure that produces a unit of work, as `SignalProducer`, to be
	///              executed by the `Action`.
	public init<State: PropertyProtocol>(strategy: ExecutionStrategy = .exclusive, state: State, enabledIf isEnabled: @escaping (State.Value) -> Bool, execute: @escaping (State.Value, Input) -> SignalProducer<Output, Error>) {
		let isUserEnabled = isEnabled

		let actionState = MutableProperty(ActionState<State.Value>(queueCapacity: strategy.queueCapacity, value: state.value))
		self.isEnabled = actionState.map { $0.isEnabled }

		// `isExecuting` has its own backing so that when the observer of `isExecuting`
		// synchronously affects the action state, the signal of the action state does not
		// deadlock due to the recursion.
		let isExecuting = MutableProperty(false)
		self.isExecuting = Property(capturing: isExecuting)

		let disposable = CompositeDisposable()
		lifetime = Lifetime(disposable)

		let (events, eventsObserver) = Signal<Signal<Output, Error>.Event, NoError>.pipe()
		let (disabledErrors, disabledErrorsObserver) = Signal<(), NoError>.pipe()

		self.events = events
		self.disabledErrors = disabledErrors

		values = events.filterMap { $0.value }
		errors = events.filterMap { $0.error }
		completed = events.filterMap { $0.isCompleted ? () : nil }

		let stateDisposable = state.producer.startWithValues { value in
			actionState.modify { state in
				state.value = value
				state.isUserEnabled = isUserEnabled(value)
			}
		}

		disposable += stateDisposable
		disposable += eventsObserver.sendCompleted
		disposable += disabledErrorsObserver.sendCompleted

		// An `Action` retains its state property until it deinitializes.
		disposable += { _ = state }

		let (workSignal, workDispatcher) = Signal<SignalProducer<Never, NoError>, NoError>.pipe()
		self.workDispatcher = workDispatcher

		// A signal of completables used to serialize the work.
		workSignal
			.flatten(strategy.flattenStrategy)
			.observeCompleted(disposable.dispose)

		self.execute = { action, input in
			return SignalProducer { observer, lifetime in
				var notifiesExecutionState = false

				func didSet() -> Void {
					if notifiesExecutionState {
						isExecuting.value = true
					}
				}

				let appliedProducer: SignalProducer<Output, Error>? = actionState.modify(didSet: didSet) { state in
					guard state.isEnabled else {
						return nil
					}

					// Increment the executing worker count.

					if state.executingCount == 0 {
						notifiesExecutionState = true
					}

					state.executingCount += 1

					// Apply the latest state and the input to create a worker, and
					// intercept the disposal of the worker.

					return execute(state.value, input)
						.on(disposed: {
							var notifiesExecutionState = false

							func didSet() {
								if notifiesExecutionState {
									isExecuting.value = false
								}
							}

							actionState.modify(didSet: didSet) { state in
								state.executingCount -= 1

								if state.executingCount == 0 {
									notifiesExecutionState = true
								}
							}
						})
				}

				guard let producer = appliedProducer else {
					observer.send(error: .disabled)
					disabledErrorsObserver.send(value: ())
					return
				}

				workDispatcher.send(value: SignalProducer { workStatus, workLifetime in
					let handle = producer.start { event in
						observer.action(event.mapError(ActionError.producerFailed))
						eventsObserver.send(value: event)
					}

					workLifetime.observeEnded(handle.dispose)
					lifetime.observeEnded(workStatus.sendCompleted)
				})
			}
		}
	}

	deinit {
		workDispatcher.sendCompleted()
	}

	/// Initializes an `Action` that would be conditionally enabled.
	///
	/// When the `Action` is asked to start the execution with an input value, a unit of
	/// work — represented by a `SignalProducer` — would be created by invoking
	/// `execute` with the input value.
	///
	/// - parameters:
	///   - isEnabled: A property which determines the availability of the `Action`.
	///   - execute: A closure that produces a unit of work, as `SignalProducer`, to be
	///              executed by the `Action`.
	public convenience init<P: PropertyProtocol>(enabledIf isEnabled: P, execute: @escaping (Input) -> SignalProducer<Output, Error>) where P.Value == Bool {
		self.init(state: isEnabled, enabledIf: { $0 }) { _, input in
			execute(input)
		}
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
		return execute(self, input)
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
