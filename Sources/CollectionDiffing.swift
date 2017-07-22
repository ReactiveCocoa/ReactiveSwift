import Foundation
import Result

/// Represents an atomic batch of changes made to a collection.
///
/// A collection delta contains relative positions of elements within the collection. It
/// is safe to use these offsets directly as indices when `Elements` is statically known
/// to be container types like `Array` and `ContiguousArray`. However, the offsets should
/// not be used directly in a generic context. Refer to the documentations of these
/// offsets for how they should be consumed correctly.
///
/// The change history associated with the first delta received by any given observation
/// is generally irrelevant. Observations should special case the first delta as a
/// complete replacement, or whatever semantic that fits their purpose.
///
/// The family of collection delta operators guarantees that a reference to the previous
/// state of the collection, via `previous`, is always available in the second and later
/// delta received by any given observation.
public struct CollectionDelta<Elements: Collection> {
	/// The collection prior to the changes, or `nil` if the collection has not ever been
	/// changed before.
	///
	/// - important: `previous` is guaranteed not to be `nil` if `self` is the second or
	///              later delta that you have received for a given observation.
	public let previous: Elements?

	/// The collection with the changes applied.
	public let current: Elements

	/// The relative positions of inserted elements **after** the removals were applied.
	/// These are valid only with the `current` snapshot.
	///
	/// - important: To obtain the actual index, you must query the `index(_:offsetBy:)`
	///              method on `current`.
	public var inserts = IndexSet()

	/// The relative positions of removed elements **prior to** any changes being applied.
	/// These are valid only with the `previous` snapshot.
	///
	/// - important: To obtain the actual index, you must query the `index(_:offsetBy:)`
	///              method on `previous`.
	public var removals = IndexSet()

	/// The relative positions of mutations. These are valid with both the `previous` and
	/// the `current` snapshot.
	///
	/// Mutations imply the same relative position, but the actual indexes could be
	/// different after the changes were applied.
	///
	/// - important: To obtain the actual index, you must query the `index(_:offsetBy:)`
	///              method on either `previous` or `current`, depending on whether the
	///              old value or the new value is the interest.
	public var mutations = IndexSet()

	/// The relative movements. The `previous` offsets are valid with the `previous`
	/// snapshot, and the `current` offsets are valid with the `current` snapshot.
	///
	/// - important: To obtain the actual index, you must query the `index(_:offsetBy:)`
	///              method on either `previous` or `current` as appropriate.
	public var moves = [(previous: Int, current: Int, mutated: Bool)]()

	public init(previous: Elements?, current: Elements) {
		self.current = current
		self.previous = previous
	}
}

/// A protocol that can be used to constrain associated types as collection deltas.
public protocol CollectionDeltaProtocol {
	associatedtype Elements: Collection

	var event: CollectionDelta<Elements> { get }
}

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
	public func diff() -> Signal<CollectionDelta<Value>, Error> {
		return diff(HashableDiffKeyGenerator<Value>.self, EquatableComparator<Value.Iterator.Element>.self)
	}
}

extension Signal where Value: Collection, Value.Iterator.Element: AnyObject, Value.Indices.Iterator.Element == Value.Index {
	/// Compute the difference of `self` with regard to `old` by object identity.
	///
	/// - precondition: The collection type must exhibit array semantics.
	///
	/// - complexity: O(n) time and space.
	public func diff() -> Signal<CollectionDelta<Value>, Error> {
		return diff(ObjectIdentityDiffKeyGenerator<Value>.self, ObjectIdentityComparator<Value.Iterator.Element>.self)
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
	public func diff(comparingBy strategy: ObjectDiffStrategy = .value) -> Signal<CollectionDelta<Value>, Error> {
		switch strategy.kind {
		case .value:
			return diff(ObjectIdentityDiffKeyGenerator<Value>.self, EquatableComparator<Value.Iterator.Element>.self)
		case .identity:
			return diff(ObjectIdentityDiffKeyGenerator<Value>.self, ObjectIdentityComparator<Value.Iterator.Element>.self)
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
	public func diff(identifyingBy identifyingStrategy: ObjectDiffStrategy = .identity, comparingBy comparingStrategy: ObjectDiffStrategy = .value) -> Signal<CollectionDelta<Value>, Error> {
		switch (identifyingStrategy.kind, comparingStrategy.kind) {
		case (.value, .value):
			return diff(HashableDiffKeyGenerator<Value>.self, EquatableComparator<Value.Iterator.Element>.self)
		case (.value, .identity):
			return diff(HashableDiffKeyGenerator<Value>.self, ObjectIdentityComparator<Value.Iterator.Element>.self)
		case (.identity, .identity):
			return diff(ObjectIdentityDiffKeyGenerator<Value>.self, ObjectIdentityComparator<Value.Iterator.Element>.self)
		case (.identity, .value):
			return diff(ObjectIdentityDiffKeyGenerator<Value>.self, EquatableComparator<Value.Iterator.Element>.self)
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
	public func diff<KeyGenerator: CollectionDiffKeyGenerator, Comparator: CollectionDiffComparator>(_ keyGenerator: KeyGenerator.Type, _ comparator: Comparator.Type) -> Signal<CollectionDelta<Value>, Error> where KeyGenerator.Element == Value.Iterator.Element, Comparator.Element == Value.Iterator.Element {
		return Signal<CollectionDelta<Value>, Error> { observer in
			var previous: Value?

			return self.observe { event in
				switch event {
				case let .value(elements):
					if let previous = previous {
						observer.send(value: Value.diff(previous: previous, current: elements, using: KeyGenerator.self, using: Comparator.self))
					} else {
						observer.send(value: CollectionDelta(previous: nil, current: elements))
					}
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
	public func diff() -> SignalProducer<CollectionDelta<Value>, Error> {
		return lift { $0.diff() }
	}
}

extension SignalProducer where Value: Collection, Value.Iterator.Element: AnyObject, Value.Indices.Iterator.Element == Value.Index {
	/// Compute the difference of `self` with regard to `old` by object identity.
	///
	/// - precondition: The collection type must exhibit array semantics.
	///
	/// - complexity: O(n) time and space.
	public func diff() -> SignalProducer<CollectionDelta<Value>, Error> {
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
	public func diff(comparingBy strategy: ObjectDiffStrategy = .value) -> SignalProducer<CollectionDelta<Value>, Error> {
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
	public func diff(identifyingBy identifyingStrategy: ObjectDiffStrategy = .identity, comparingBy comparingStrategy: ObjectDiffStrategy = .value) -> SignalProducer<CollectionDelta<Value>, Error> {
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
	public func diff<KeyGenerator: CollectionDiffKeyGenerator, Comparator: CollectionDiffComparator>(_ keyGenerator: KeyGenerator.Type, _ comparator: Comparator.Type) -> SignalProducer<CollectionDelta<Value>, Error> where KeyGenerator.Element == Value.Iterator.Element, Comparator.Element == Value.Iterator.Element {
		return lift { $0.diff(KeyGenerator.self, Comparator.self) }
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
	public func diff() -> Property<CollectionDelta<Value>> {
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
	public func diff() -> Property<CollectionDelta<Value>> {
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
	public func diff(comparingBy strategy: ObjectDiffStrategy = .value) -> Property<CollectionDelta<Value>> {
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
	public func diff(identifyingBy identifyingStrategy: ObjectDiffStrategy = .identity, comparingBy comparingStrategy: ObjectDiffStrategy = .value) -> Property<CollectionDelta<Value>> {
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
	public func diff<KeyGenerator: CollectionDiffKeyGenerator, Comparator: CollectionDiffComparator>(_ keyGenerator: KeyGenerator.Type, _ comparator: Comparator.Type) -> Property<CollectionDelta<Value>> where KeyGenerator.Element == Value.Iterator.Element, Comparator.Element == Value.Iterator.Element {
		return lift { $0.diff(KeyGenerator.self, Comparator.self) }
	}
}

// MARK: - Implementation details

// The key equality implies only referential equality. But the value equality of the
// uniquely identified element across snapshots is uncertain. It is pretty common to diff
// elements with constant unique identifiers but changing contents. For example, we may
// have an array of `Conversation`s, identified by the backend ID, that is constantly
// updated with the latest messages pushed from the backend. So our diffing algorithm
// must have an additional mean to test elements for value equality.

public protocol CollectionDiffKeyGenerator {
	associatedtype Element
	associatedtype Key: Hashable

	static func key(for element: Element) -> Key
}

public protocol CollectionDiffComparator {
	associatedtype Element

	static func isEqual(_ left: Element, _ right: Element) -> Bool
}

private final class DiffEntry {
	var occurenceInOld = 0
	var occurenceInNew = 0
	var locationInOld: Int?
}

private enum DiffReference {
	case remote(Int)
	case table(DiffEntry)
}

private enum EquatableComparator<E: Equatable>: CollectionDiffComparator {
	static func isEqual(_ left: E, _ right: E) -> Bool {
		return left == right
	}
}

private enum ObjectIdentityComparator<E: AnyObject>: CollectionDiffComparator {
	static func isEqual(_ left: E, _ right: E) -> Bool {
		return left === right
	}
}

private enum HashableDiffKeyGenerator<E: Collection>: CollectionDiffKeyGenerator where E.Iterator.Element: Hashable, E.Index == E.Indices.Iterator.Element {
	typealias Elements = E

	static func key(for element: Elements.Iterator.Element) -> Elements.Iterator.Element {
		return element
	}
}

private enum ObjectIdentityDiffKeyGenerator<E: Collection>: CollectionDiffKeyGenerator where E.Iterator.Element: AnyObject, E.Index == E.Indices.Iterator.Element {
	typealias Elements = E

	static func key(for element: Elements.Iterator.Element) -> ObjectIdentifier {
		return ObjectIdentifier(element)
	}
}

// FIXME: Swift 4 Associated type constraints
// extension CollectionDiffer {
extension Collection where Index == Indices.Iterator.Element {
	public static func diff<KeyGenerator: CollectionDiffKeyGenerator, Comparator: CollectionDiffComparator>(
		previous: Self,
		current: Self,
		using _: KeyGenerator.Type,
		using _: Comparator.Type
	) -> CollectionDelta<Self> where KeyGenerator.Element == Iterator.Element, Comparator.Element == Iterator.Element {
		switch Self.self {
		case is Array<Iterator.Element>.Type:
			fallthrough
		case is ContiguousArray<Iterator.Element>.Type:
			// The standard library does not copy the content when `ContiguousArray.init`
			// is passed an `Array` backed by a native buffer or a `ContiguousArray`. So
			// we exploit this optimization to obtain an unsafe buffer pointer.
			//
			// `ArraySlice` is not supported at the moment, since it may have a non-zero
			// start index that needs to be taken care of.
			return ContiguousArray(previous).withUnsafeBufferPointer { previousBuffer in
				return ContiguousArray(current).withUnsafeBufferPointer { currentBuffer in
					return diff(previous: previousBuffer,
								current: currentBuffer,
								delta: CollectionDelta(previous: previous, current: current),
								using: KeyGenerator.self,
								using: Comparator.self)
				}
			}

		default:
			return diff(previous: previous,
						current: current,
						delta: CollectionDelta(previous: previous, current: current),
						using: KeyGenerator.self,
						using: Comparator.self)
		}
	}

	private static func diff<View: Collection, KeyGenerator: CollectionDiffKeyGenerator, Comparator: CollectionDiffComparator>(
		previous: View,
		current: View,
		delta: CollectionDelta<Self>,
		using _: KeyGenerator.Type,
		using _: Comparator.Type
	) -> CollectionDelta<Self> where KeyGenerator.Element == Iterator.Element, Comparator.Element == Iterator.Element, View.Iterator.Element == Iterator.Element, View.Index == View.Indices.Iterator.Element {
		var table: [KeyGenerator.Key: DiffEntry] = Dictionary(minimumCapacity: Int(current.count))
		var oldReferences: [DiffReference] = []
		var newReferences: [DiffReference] = []

		oldReferences.reserveCapacity(Int(previous.count))
		newReferences.reserveCapacity(Int(current.count))

		// Pass 1: Scan the new snapshot.
		for element in current {
			let key = KeyGenerator.key(for: element)

			let entry: DiffEntry
			if let index = table.index(forKey: key) {
				entry = table[index].value
			} else {
				entry = DiffEntry()
				table[key] = entry
			}

			entry.occurenceInNew += 1
			newReferences.append(.table(entry))
		}

		// Pass 2: Scan the old snapshot.
		for (offset, index) in previous.indices.enumerated() {
			let key = KeyGenerator.key(for: previous[index])

			let entry: DiffEntry
			if let index = table.index(forKey: key) {
				entry = table[index].value
			} else {
				entry = DiffEntry()
				table[key] = entry
			}

			entry.occurenceInOld += 1
			entry.locationInOld = offset
			oldReferences.append(.table(entry))
		}

		// Pass 3: Single-occurence lines
		for newPosition in newReferences.startIndex ..< newReferences.endIndex {
			switch newReferences[newPosition] {
			case let .table(entry):
				if entry.occurenceInNew == 1 && entry.occurenceInNew == entry.occurenceInOld {
					let oldPosition = entry.locationInOld!
					newReferences[newPosition] = .remote(oldPosition)
					oldReferences[oldPosition] = .remote(newPosition)
				}

			case .remote:
				break
			}
		}

		var diff = delta

		// Final Pass: Compute diff.
		for position in oldReferences.indices {
			switch oldReferences[position] {
			case .table:
				// Deleted
				diff.removals.insert(position)

			case let .remote(newPosition):
				let previousIndex = previous.index(previous.startIndex, offsetBy: View.IndexDistance(position))
				let currentIndex = current.index(current.startIndex, offsetBy: View.IndexDistance(position))
				let areEqual = Comparator.isEqual(previous[previousIndex], current[currentIndex])
				let isInPlace = newPosition == position

				switch (areEqual, isInPlace) {
				case (false, true):
					diff.mutations.insert(position)

				case (_, false):
					diff.moves.append((previous: position, current: newPosition, mutated: !areEqual))

				case (true, true):
					break
				}
			}
		}

		for position in newReferences.indices {
			if case .table = newReferences[position] {
				diff.inserts.insert(position)
			}
		}

		return diff
	}
}

#if !swift(>=3.2)
	extension SignedInteger {
		fileprivate init<I: SignedInteger>(_ integer: I) {
			self.init(integer.toIntMax())
		}
	}
#endif
