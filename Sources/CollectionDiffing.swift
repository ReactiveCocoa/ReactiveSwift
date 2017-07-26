import Foundation
import Result

/// The comparison strategies used by the collection diffing operators on collections
/// that contain `Hashable` objects.
public struct ObjectDiffStrategy {
	fileprivate enum Kind {
		case identity
		case value
	}

	/// Compare the elements by their object identity.
	public static let identity = ObjectDiffStrategy(kind: .identity)

	/// Compare the elements by their value equality.
	public static let value = ObjectDiffStrategy(kind: .value)

	fileprivate let kind: Kind

	private init(kind: Kind) {
		self.kind = kind
	}
}

extension Signal where Value: Collection, Value.Iterator.Element: Hashable, Value.Indices.Iterator.Element == Value.Index {
	/// Compute the difference of `self` with regard to `old` by value equality.
	///
	/// `diff(with:)` works best with collections that contain unique values.
	///
	/// If the elements are repeated per the definition of `Element.==`, `diff(with:)`
	/// cannot guarantee a deterministic stable order, so these would all be uniformly
	/// treated as removals and inserts.
	///
	/// - precondition: The collection type must exhibit array semantics.
	///
	/// - complexity: O(n) time and space.
	public func diff() -> Signal<Snapshot<Value, Changeset>, Error> {
		return diff(identifier: { $0 }, areEqual: ==)
	}
}

extension Signal where Value: Collection, Value.Iterator.Element: AnyObject, Value.Indices.Iterator.Element == Value.Index {
	/// Compute the difference of `self` with regard to `old` by object identity.
	///
	/// - precondition: The collection type must exhibit array semantics.
	///
	/// - complexity: O(n) time and space.
	public func diff() -> Signal<Snapshot<Value, Changeset>, Error> {
		return diff(identifier: ObjectIdentifier.init, areEqual: ===)
	}
}

extension Signal where Value: Collection, Value.Iterator.Element: AnyObject & Equatable, Value.Indices.Iterator.Element == Value.Index {
	/// Compute the difference of `self` with regard to `old` using the given comparing
	/// strategy. The elements are identified by their object identity.
	///
	/// - precondition: The collection type must exhibit array semantics.
	///
	/// - parameters:
	///   - strategy: The comparing strategy to use.
	///
	/// - complexity: O(n) time and space.
	public func diff(comparingBy strategy: ObjectDiffStrategy = .value) -> Signal<Snapshot<Value, Changeset>, Error> {
		switch strategy.kind {
		case .value:
			return diff(identifier: ObjectIdentifier.init, areEqual: ==)
		case .identity:
			return diff(identifier: ObjectIdentifier.init, areEqual: ===)
		}
	}
}

extension Signal where Value: Collection, Value.Iterator.Element: AnyObject & Hashable, Value.Indices.Iterator.Element == Value.Index {
	/// Compute the difference of `self` with regard to `old` using the given comparing
	/// strategy. The elements are identified by the given identifying strategy.
	///
	/// - precondition: The collection type must exhibit array semantics.
	///
	/// - parameters:
	///   - identifyingStrategy: The identifying strategy to use.
	///   - comparingStrategy: The comparingStrategy strategy to use.
	///
	/// - complexity: O(n) time and space.
	public func diff(identifyingBy identifyingStrategy: ObjectDiffStrategy = .identity, comparingBy comparingStrategy: ObjectDiffStrategy = .value) -> Signal<Snapshot<Value, Changeset>, Error> {
		switch (identifyingStrategy.kind, comparingStrategy.kind) {
		case (.value, .value):
			return diff(identifier: { $0 }, areEqual: ==)
		case (.value, .identity):
			return diff(identifier: { $0 }, areEqual: ===)
		case (.identity, .identity):
			return diff(identifier: ObjectIdentifier.init, areEqual: ===)
		case (.identity, .value):
			return diff(identifier: ObjectIdentifier.init, areEqual: ==)
		}
	}
}

extension Signal where Value: Collection, Value.Indices.Iterator.Element == Value.Index {
	/// Compute the difference of `self` with regard to `old` by value equality.
	///
	/// `diff(with:)` works best with collections that contain unique values.
	///
	/// If the elements are repeated per the definition of `Element.==`, `diff(with:)`
	/// cannot guarantee a deterministic stable order, so these would all be uniformly
	/// treated as removals and inserts.
	///
	/// - precondition: The collection type must exhibit array semantics.
	///
	/// - parameters:
	///   - keyGenerator: A unique identifier generator to apply on elements.
	///   - comparator: A comparator that evaluates two elements for equality.
	///
	/// - complexity: O(n) time and space.
	public func diff<Identifier: Hashable>(identifier: @escaping (Value.Iterator.Element) -> Identifier, areEqual: @escaping (Value.Iterator.Element, Value.Iterator.Element) -> Bool) -> Signal<Snapshot<Value, Changeset>, Error> {
		return Signal<Snapshot<Value, Changeset>, Error> { observer in
			var previous: Value?

			return self.observe { event in
				switch event {
				case let .value(elements):
					let changeset: Changeset

					if let previous = previous {
						changeset = Changeset(previous: previous, current: elements, identifier: identifier, areEqual: areEqual)
					} else {
						changeset = Changeset(initial: elements)
					}

					observer.send(value: Snapshot(previous: previous, current: elements, changeset: changeset))
					previous = elements
				case .completed:
					observer.sendCompleted()
				case let .failed(error):
					observer.send(error: error)
				case .interrupted:
					observer.sendInterrupted()
				}
			}
		}
	}
}

extension SignalProducer where Value: Collection, Value.Iterator.Element: Hashable, Value.Indices.Iterator.Element == Value.Index {
	/// Compute the difference of `self` with regard to `old` by value equality.
	///
	/// `diff(with:)` works best with collections that contain unique values.
	///
	/// If the elements are repeated per the definition of `Element.==`, `diff(with:)`
	/// cannot guarantee a deterministic stable order, so these would all be uniformly
	/// treated as removals and inserts.
	///
	/// - precondition: The collection type must exhibit array semantics.	
	///
	/// - complexity: O(n) time and space.
	public func diff() -> SignalProducer<Snapshot<Value, Changeset>, Error> {
		return lift { $0.diff() }
	}
}

extension SignalProducer where Value: Collection, Value.Iterator.Element: AnyObject, Value.Indices.Iterator.Element == Value.Index {
	/// Compute the difference of `self` with regard to `old` by object identity.
	///
	/// - precondition: The collection type must exhibit array semantics.
	///
	/// - complexity: O(n) time and space.
	public func diff() -> SignalProducer<Snapshot<Value, Changeset>, Error> {
		return lift { $0.diff() }
	}
}

extension SignalProducer where Value: Collection, Value.Iterator.Element: AnyObject & Equatable, Value.Indices.Iterator.Element == Value.Index {
	/// Compute the difference of `self` with regard to `old` using the given comparing
	/// strategy. The elements are identified by their object identity.
	///
	/// - precondition: The collection type must exhibit array semantics.
	///
	/// - parameters:
	///   - strategy: The comparing strategy to use.
	///
	/// - complexity: O(n) time and space.
	public func diff(comparingBy strategy: ObjectDiffStrategy = .value) -> SignalProducer<Snapshot<Value, Changeset>, Error> {
		return lift { $0.diff(comparingBy: strategy) }
	}
}

extension SignalProducer where Value: Collection, Value.Iterator.Element: AnyObject & Hashable, Value.Indices.Iterator.Element == Value.Index {
	/// Compute the difference of `self` with regard to `old` using the given comparing
	/// strategy. The elements are identified by the given identifying strategy.
	///
	/// - precondition: The collection type must exhibit array semantics.
	///
	/// - parameters:
	///   - identifyingStrategy: The identifying strategy to use.
	///   - comparingStrategy: The comparingStrategy strategy to use.
	///
	/// - complexity: O(n) time and space.
	public func diff(identifyingBy identifyingStrategy: ObjectDiffStrategy = .identity, comparingBy comparingStrategy: ObjectDiffStrategy = .value) -> SignalProducer<Snapshot<Value, Changeset>, Error> {
		return lift { $0.diff(identifyingBy: identifyingStrategy, comparingBy: comparingStrategy) }
	}
}

extension SignalProducer where Value: Collection, Value.Indices.Iterator.Element == Value.Index {
	/// Compute the difference of `self` with regard to `old` by value equality.
	///
	/// `diff(with:)` works best with collections that contain unique values.
	///
	/// If the elements are repeated per the definition of `Element.==`, `diff(with:)`
	/// cannot guarantee a deterministic stable order, so these would all be uniformly
	/// treated as removals and inserts.
	///
	/// - precondition: The collection type must exhibit array semantics.
	///
	/// - parameters:
	///   - keyGenerator: A unique identifier generator to apply on elements.
	///   - comparator: A comparator that evaluates two elements for equality.
	///
	/// - complexity: O(n) time and space.
	public func diff<Identifier: Hashable>(identifier: @escaping (Value.Iterator.Element) -> Identifier, areEqual: @escaping (Value.Iterator.Element, Value.Iterator.Element) -> Bool) -> SignalProducer<Snapshot<Value, Changeset>, Error> {
		return lift { $0.diff(identifier: identifier, areEqual: areEqual) }
	}
}

extension PropertyProtocol where Value: Collection, Value.Iterator.Element: Hashable, Value.Indices.Iterator.Element == Value.Index {
	/// Compute the difference of `self` with regard to `old` by value equality.
	///
	/// `diff(with:)` works best with collections that contain unique values.
	///
	/// If the elements are repeated per the definition of `Element.==`, `diff(with:)`
	/// cannot guarantee a deterministic stable order, so these would all be uniformly
	/// treated as removals and inserts.
	///
	/// - precondition: The collection type must exhibit array semantics.
	///
	/// - complexity: O(n) time and space.
	public func diff() -> Property<Snapshot<Value, Changeset>> {
		return lift { $0.diff() }
	}
}

// FIXME: Swift 4 compiler workaround for `diff` overloads.
// extension PropertyProtocol ...
extension _PropertyProtocol where Value: Collection, Value.Iterator.Element: AnyObject, Value.Indices.Iterator.Element == Value.Index {
	/// Compute the difference of `self` with regard to `old` by object identity.
	///
	/// - precondition: The collection type must exhibit array semantics.
	///
	/// - complexity: O(n) time and space.
	public func diff() -> Property<Snapshot<Value, Changeset>> {
		return lift { $0.diff() }
	}
}

// FIXME: Swift 4 compiler workaround for `diff` overloads.
// extension PropertyProtocol ...
extension _PropertyProtocol where Value: Collection, Value.Iterator.Element: AnyObject & Equatable, Value.Indices.Iterator.Element == Value.Index {
	/// Compute the difference of `self` with regard to `old` using the given comparing
	/// strategy. The elements are identified by their object identity.
	///
	/// - precondition: The collection type must exhibit array semantics.
	///
	/// - parameters:
	///   - strategy: The comparing strategy to use.
	///
	/// - complexity: O(n) time and space.
	public func diff(comparingBy strategy: ObjectDiffStrategy = .value) -> Property<Snapshot<Value, Changeset>> {
		return lift { $0.diff(comparingBy: strategy) }
	}
}

// FIXME: Swift 4 compiler workaround for `diff` overloads.
// extension PropertyProtocol ...
extension _PropertyProtocol where Value: Collection, Value.Iterator.Element: AnyObject & Hashable, Value.Indices.Iterator.Element == Value.Index {
	/// Compute the difference of `self` with regard to `old` using the given comparing
	/// strategy. The elements are identified by the given identifying strategy.
	///
	/// - precondition: The collection type must exhibit array semantics.
	///
	/// - parameters:
	///   - identifyingStrategy: The identifying strategy to use.
	///   - comparingStrategy: The comparingStrategy strategy to use.
	///
	/// - complexity: O(n) time and space.
	public func diff(identifyingBy identifyingStrategy: ObjectDiffStrategy = .identity, comparingBy comparingStrategy: ObjectDiffStrategy = .value) -> Property<Snapshot<Value, Changeset>> {
		return lift { $0.diff(identifyingBy: identifyingStrategy, comparingBy: comparingStrategy) }
	}
}

extension PropertyProtocol where Value: Collection, Value.Indices.Iterator.Element == Value.Index {
	/// Compute the difference of `self` with regard to `old` by value equality.
	///
	/// `diff(with:)` works best with collections that contain unique values.
	///
	/// If the elements are repeated per the definition of `Element.==`, `diff(with:)`
	/// cannot guarantee a deterministic stable order, so these would all be uniformly
	/// treated as removals and inserts.
	///
	/// - precondition: The collection type must exhibit array semantics.
	///
	/// - parameters:
	///   - keyGenerator: A unique identifier generator to apply on elements.
	///   - comparator: A comparator that evaluates two elements for equality.
	///
	/// - complexity: O(n) time and space.
	public func diff<Identifier: Hashable>(identifier: @escaping (Value.Iterator.Element) -> Identifier, areEqual: @escaping (Value.Iterator.Element, Value.Iterator.Element) -> Bool) -> Property<Snapshot<Value, Changeset>> {
		return lift { $0.diff(identifier: identifier, areEqual: areEqual) }
	}
}
