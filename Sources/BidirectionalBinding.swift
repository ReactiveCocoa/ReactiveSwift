import Result

private final class BidirectionalBindingArbitrator<LHSModifier, RHSModifier> where LHSModifier: BidirectionalBindingEndpointModifier, RHSModifier: BidirectionalBindingEndpointModifier, LHSModifier.Value == RHSModifier.Value {
	private typealias Value = LHSModifier.Value
	private typealias _Self = BidirectionalBindingArbitrator<LHSModifier, RHSModifier>

	private enum Container {
		case left(Value)
		case right(Value)
	}

	private let (endSignal, endObserver) = Signal<(), NoError>.pipe()
	private let policy: BidirectionalBindingPolicy
	let disposable: ActionDisposable

	private var isLHSWritingBack: Bool
	private var isRHSWritingBack: Bool

	private let outstandingLHSWriteback: SerialDisposable
	private let outstandingRHSWriteback: SerialDisposable

	private var leftValue: Value?
	private var rightValue: Value?

	private let lock: NSRecursiveLock?
	private var writeForeign: (_Self, Container) -> Void

	init(left: BidirectionalBindingEndpoint<LHSModifier>, right: BidirectionalBindingEndpoint<RHSModifier>, policy: BidirectionalBindingPolicy) {
		let leftScheduler = left.scheduler ?? ImmediateScheduler()
		let rightScheduler = right.scheduler ?? ImmediateScheduler()

		self.lock = leftScheduler is ImmediateScheduler && rightScheduler is ImmediateScheduler ? nil : NSRecursiveLock()

		self.isLHSWritingBack = false
		self.isRHSWritingBack = false
		self.outstandingLHSWriteback = SerialDisposable()
		self.outstandingRHSWriteback = SerialDisposable()

		self.policy = policy
		self.disposable = ActionDisposable(action: endObserver.sendCompleted)
		left.lifetime.observeEnded(endObserver.sendCompleted)
		right.lifetime.observeEnded(endObserver.sendCompleted)

		writeForeign = { [leftSetter = left.setter, rightSetter = right.setter] arbitrator, newValue in
			// Threading notes:
			//
			// 1. `leftValue` and `rightValue` must be filled before assigning scheduler
			//    tokens to the serial disposables.
			//
			// 2. Clearing `leftValue` and `rightValue` must be guarded by the binding
			//    lock.
			switch newValue {
			case let .left(newValue):
				arbitrator.leftValue = newValue
				arbitrator.outstandingLHSWriteback.inner = leftScheduler.schedule {
					leftSetter { value in
						// The observer is responsible of clearing the flag.
						arbitrator.isLHSWritingBack = true
						value = newValue
					}
					arbitrator.outstandingLHSWriteback.inner = nil

					assert(!arbitrator.isLHSWritingBack,
					       "Expected the modifier signal to emit a modifier synchronously with the mutation. Caught none.")

					arbitrator.lock?.lock()
					arbitrator.leftValue = nil
					arbitrator.lock?.unlock()
				}

			case let .right(newValue):
				arbitrator.rightValue = newValue
				arbitrator.outstandingRHSWriteback.inner = rightScheduler.schedule {
					rightSetter { value in
						arbitrator.isRHSWritingBack = true
						value = newValue
					}
					arbitrator.outstandingRHSWriteback.inner = nil

					assert(!arbitrator.isRHSWritingBack,
					       "Expected the modifier signal to emit a modifier synchronously with the mutation. Caught none.")

					arbitrator.lock?.lock()
					arbitrator.rightValue = nil
					arbitrator.lock?.unlock()
				}
			}
		}

		// The modifier producer is required to emit synchronously the current value for
		// deterministic initial value resolution.
		switch policy {
		case .preferLeft: isRHSWritingBack = true
		case .preferRight: isLHSWritingBack = true
		}

		left.values
			.take(until: endSignal)
			.start(on: leftScheduler)
			.startWithValues { modifier in
				guard !self.isLHSWritingBack else {
					self.isLHSWritingBack = false
					return
				}

				modifier.resolve { value in
					return self.resolve(.left(value))
				}
			}

		right.values
			.take(until: endSignal)
			.start(on: rightScheduler)
			.startWithValues { modifier in
				guard !self.isRHSWritingBack else {
					self.isRHSWritingBack = false
					return
				}

				modifier.resolve { value in
					return self.resolve(.right(value))
				}
			}
	}

	private func resolve(_ attemptedValue: Container) -> Value? {
		lock?.lock()
		defer { lock?.unlock() }

		// Abort writes only if the source endpoint is not preferred, and the last written
		// value is from the preferred endpoint.

		let hasPendingLHSWriteback = outstandingLHSWriteback.inner?.isDisposed ?? false
		let hasPendingRHSWriteback = outstandingRHSWriteback.inner?.isDisposed ?? false

		switch (hasPendingLHSWriteback, hasPendingRHSWriteback, attemptedValue, policy) {
		case (_, true, .left, .preferRight):
			// RHS has pending writeback; LHS attempts to overwrite; Policy: Prefer RHS.
			outstandingLHSWriteback.inner = nil
			return rightValue!

		case (true, _, .right, .preferLeft):
			// LHS has pending writeback; RHS attempts to overwrite; Policy: Prefer LHS.
			outstandingRHSWriteback.inner = nil
			return leftValue!

		case let (_, _, .left(value), _):
			writeForeign(self, .right(value))

		case let (_, _, .right(value), _):
			writeForeign(self, .left(value))
		}
		
		return nil
	}
}

// The bidirectional partial binding operator. It is used in conjunction with `<~` which
// completes partial bindings.
infix operator ~>: BindingPrecedence

/// Represents an entity that can form a bidirectional value binding with another entity.
/// The binding monitors mutations of `self` through the modifier signal provided by
/// `self`, while it accepts mutations from the binding through its binding target.
///
/// To establish a bidirectional binding, use the `~>` operator to construct a partial
/// binding with a binding policy and an endpoint. Then use `<~` to complete the partial
/// binding with another endpoint.
///
/// ```
/// let 🌈 = MutableProperty<String>("🌈")
/// let 🦄 = MutableProperty<String>("🦄")
///
/// let partialBinding = .preferLeft ~> 🌈
/// let disposable = 🦄 <~ partialBinding
///
/// // Inlined version
/// 🦄 <~ .preferLeft ~> 🌈
///
/// // The initial value is resolved using the `preferLeft`
/// // binding policy.
/// assert(🦄.value == "🦄")
/// assert(🌈.value == "🦄")
/// ```
///
/// # Synchronous and asynchronous binding
/// A bidirectional binding is synchronous as long as both endpoints are synchronous. If
/// any of the endpoints is bound to a scheduler, except `ImmediateScheduler`, the binding
/// is considered asynchronous.
///
/// A bidirectional binding supports both kinds of bindings, and a binding policy is
/// mandatory for the binding system to resolve the initial value and any subsequent
/// conflict. Two policies are available: `preferLeft` and `preferRight`.
///
/// # Multi Binding Support
/// Multi-binding is supported by synchronous bindings.
///
/// If any of the binding is asynchronous, it would depend on whether the endpoints
/// support resolving multi-binding conflicts. The protocol does not mandate the
/// resolution, and conforming types may opt out and trap at runtime should such conflict
/// have been detected.
///
/// # Consistency Gaurantees
public protocol BidirectionalBindingEndpointProvider {
	associatedtype Modifier: BidirectionalBindingEndpointModifier

	var bindingEndpoint: BidirectionalBindingEndpoint<Modifier> { get }
}

public protocol BidirectionalBindingEndpointModifier {
	associatedtype Value

	func resolve(_ action: (Value) -> Value?)
}

public struct BidirectionalBindingEndpoint<Modifier: BidirectionalBindingEndpointModifier> {
	fileprivate let scheduler: Scheduler?
	fileprivate let values: SignalProducer<Modifier, NoError>
	fileprivate let setter: ((inout Modifier.Value) -> Void) -> Void
	fileprivate let lifetime: Lifetime
}

public enum BidirectionalBindingPolicy {
	case preferLeft
	case preferRight
}

// Operator implementations.
extension BidirectionalBindingEndpointProvider {
	public static func ~> (policy: BidirectionalBindingPolicy, provider: Self) -> PartialBidirectionalBinding<Modifier> {
		return PartialBidirectionalBinding(provider.bindingEndpoint, policy: policy)
	}
}

public struct PartialBidirectionalBinding<Modifier: BidirectionalBindingEndpointModifier> {
	fileprivate let policy: BidirectionalBindingPolicy
	fileprivate let endpoint: BidirectionalBindingEndpoint<Modifier>

	fileprivate init(_ endpoint: BidirectionalBindingEndpoint<Modifier>, policy: BidirectionalBindingPolicy) {
		self.policy = policy
		self.endpoint = endpoint
	}

	@discardableResult
	public static func <~ <Provider: BidirectionalBindingEndpointProvider>(
		provider: Provider,
		partialBinding: PartialBidirectionalBinding<Modifier>
	) -> Disposable? where Modifier.Value == Provider.Modifier.Value {
		let arbitrator = BidirectionalBindingArbitrator(left: provider.bindingEndpoint, right: partialBinding.endpoint, policy: partialBinding.policy)
		return arbitrator.disposable
	}
}

// Bidirectional mapped properties.

public protocol BidirectionalTransform {
	associatedtype Value1
	associatedtype Value2

	func convert(_ value: Value1) -> Value2
	func convert(_ value: Value2) -> Value1
}

public struct AnyBidirectionalTransform<A, B>: BidirectionalTransform {
	public typealias Value1 = A
	public typealias Value2 = B

	private let convert1: (Value1) -> Value2
	private let convert2: (Value2) -> Value1

	public init<Transform: BidirectionalTransform>(reversing transform: Transform) where Transform.Value2 == Value1, Transform.Value1 == Value2 {
		self.init(transform.convert, transform.convert)
	}

	public init(_ forward: @escaping (Value1) -> Value2, _ reverse: @escaping (Value2) -> Value1) {
		self.convert1 = forward
		self.convert2 = reverse
	}

	public func convert(_ value: Value1) -> Value2 {
		return convert1(value)
	}

	public func convert(_ value: Value2) -> Value1 {
		return convert2(value)
	}
}

public final class TransformingProperty<Value>: MutablePropertyProtocol {
	private let cache: Property<Value>
	private let setter: (Value) -> Void

	public var value: Value {
		get { return cache.value }
		set { setter(newValue) }
	}

	public var producer: SignalProducer<Value, NoError> {
		return cache.producer
	}

	public var signal: Signal<Value, NoError> {
		return cache.signal
	}

	public let lifetime: Lifetime

	public init<P: MutablePropertyProtocol, Transform: BidirectionalTransform>(_ property: P, _ transform: Transform) where Transform.Value1 == P.Value, Transform.Value2 == Value {
		cache = property.map(transform.convert)
		setter = { property.value = transform.convert($0) }
		lifetime = property.lifetime
	}

	public convenience init<P: MutablePropertyProtocol, Transform: BidirectionalTransform>(_ property: P, _ transform: Transform) where Transform.Value2 == P.Value, Transform.Value1 == Value {
		self.init(property, AnyBidirectionalTransform(reversing: transform))
	}
}
