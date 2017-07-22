import Foundation
import Result

/// Represents a snapshot of a collection.
///
/// The changeset associated with the first snapshot received by any given observation
/// is generally irrelevant. Observations should special case the first snapshot as a
/// complete replacement, or whatever semantic that fits their purpose.
///
/// `Snapshot` does not include a reference to the previous snapshot. If the
/// history is relevant for delta consumption, it is up to the observers to cache the
/// history on their own.
///
/// While the protocol does not bind the `Changeset` associated type with any constraint,
/// it is expected to be either a `Changeset`, or a composite of `Changeset`s for a nested
/// collection.
public struct Snapshot<Elements: Collection, Changeset>: SnapshotProtocol {
	public let elements: Elements
	public let changeset: Changeset

	public init(elements: Elements, changeset: Changeset) {
		(self.elements, self.changeset) = (elements, changeset)
	}
}

public protocol SnapshotProtocol {
	associatedtype Elements: Collection
	associatedtype Changeset

	var elements: Elements { get }
	var changeset: Changeset { get }
}

/// Represents an atomic batch of changes made to a collection.
///
/// A `Changeset` represents changes as **offsets** of elements. You may
/// subscript a collection of zero-based indexing with the offsets, e.g. `Array`. You must
/// otherwise convert the offsets into indices before subscripting.
public struct Changeset {
	/// Represents the context of a move operation applied to a collection.
	public struct Move {
		public let source: Int
		public let isMutated: Bool

		public init(source: Int, isMutated: Bool) {
			(self.source, self.isMutated) = (source, isMutated)
		}
	}

	/// The offsets of inserted elements **after** the removals were applied.
	///
	/// - important: To obtain the actual index, you must apply
	///              `Collection.index(self:_:offsetBy:)` on the current snapshot, the
	///              start index and the offset.
	public var inserts = IndexSet()

	/// The offsets of removed elements **prior to** any changes being applied.
	///
	/// - important: To obtain the actual index, you must apply
	///              `Collection.index(self:_:offsetBy:)` on the previous snapshot, the
	///              start index and the offset.
	public var removals = IndexSet()

	/// The offsets of position-invariant mutations.
	///
	/// `mutations` only implies an invariant relative position. The actual indexes can
	/// be different, depending on the collection type.
	///
	/// If an element has both changed and moved, it would be included in `moves` with an
	/// asserted mutation flag.
	///
	/// - important: To obtain the actual index, you must apply
	///              `Collection.index(self:_:offsetBy:)` on the relevant snapshot, the
	///              start index and the offset.
	public var mutations = IndexSet()

	/// The offset pairs of moves.
	///
	/// The offset pairs are recorded as a `Dictionary` keyed by the destination offset,
	/// with the source offset and a mutation flag as the associated value.
	///
	/// - important: To obtain the actual index, you must apply
	///              `Collection.index(self:_:offsetBy:)` on the relevant snapshot, the
	///              start index and the offset.
	public var moves = [Int: Move]()

	/// Whether the delta actually represents no changes.
	///
	/// Generally speaking, this is prevalent only when diffing nested collections as
	/// a placeholder for unchanged inner collections.
	public var representsNoChanges: Bool {
		return inserts.isEmpty && removals.isEmpty && mutations.isEmpty && moves.isEmpty
	}

	public init() {}

	public init<C: Collection>(initial: C) {
		inserts = IndexSet(integersIn: 0 ..< Int(initial.count))
	}
}

/// Represents an atomic batch of changes made to a sectioned collection.
public struct SectionedChangeset {
	public struct MutatedSection {
		public let changeset: Changeset
		public let source: Int
	}

	/// The changes of sections.
	///
	/// - precondition: Offsets in `sections.mutations` and `sections.moves` must have a
	///                 corresponding entry in `mutatedSections` if they represent a
	///                 mutation.
	public var sections = Changeset()

	/// The changes of items in the mutated sections.
	///
	/// - precondition: `mutatedSections` must have an entry for every mutated sections
	///                 specified by `sections.mutations` and `sections.moves`.
	public var mutatedSections: [Int: MutatedSection] = [:]

	public init(sections: Changeset = Changeset(), mutatedSections: [Int: MutatedSection] = [:]) {
		(self.sections, self.mutatedSections) = (sections, mutatedSections)
	}

	public init<C: Collection>(initial: C) {
		sections.inserts.insert(integersIn: 0 ..< Int(initial.count))
	}
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
						changeset = Value.diff(previous: previous, current: elements, identifier: identifier, areEqual: areEqual)
					} else {
						changeset = Changeset(initial: elements)
					}

					observer.send(value: Snapshot(elements: elements, changeset: changeset))
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

// MARK: - Implementation details

// The key equality implies only referential equality. But the value equality of the
// uniquely identified element across snapshots is uncertain. It is pretty common to diff
// elements with constant unique identifiers but changing contents. For example, we may
// have an array of `Conversation`s, identified by the backend ID, that is constantly
// updated with the latest messages pushed from the backend. So our diffing algorithm
// must have an additional mean to test elements for value equality.

private final class DiffEntry {
	var occurenceInOld = 0
	var occurenceInNew = 0
	var locationInOld: Int?
}

private enum DiffReference {
	case remote(Int)
	case table(DiffEntry)
}

// FIXME: Swift 4 Associated type constraints
// extension Collection {
extension Collection where Index == Indices.Iterator.Element {
	// @testable
	internal static func diff<Identifier: Hashable>(
		previous: Self,
		current: Self,
		identifier: (Iterator.Element) -> Identifier,
		areEqual: (Iterator.Element, Iterator.Element) -> Bool
	) -> Changeset {
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
					return _diff(previous: previousBuffer,
					             current: currentBuffer,
					             identifier: identifier,
					             areEqual: areEqual)
				}
			}

		default:
			return _diff(previous: previous,
			             current: current,
			             identifier: identifier,
			             areEqual: areEqual)
		}
	}

	private static func _diff<View: Collection, Identifier: Hashable>(
		previous: View,
		current: View,
		identifier: (Iterator.Element) -> Identifier,
		areEqual: (Iterator.Element, Iterator.Element) -> Bool
	) -> Changeset where View.Iterator.Element == Iterator.Element, View.Index == View.Indices.Iterator.Element {
		var table: [Identifier: DiffEntry] = Dictionary(minimumCapacity: Int(current.count))
		var oldReferences: [DiffReference] = []
		var newReferences: [DiffReference] = []

		oldReferences.reserveCapacity(Int(previous.count))
		newReferences.reserveCapacity(Int(current.count))

		func tableEntry(for identifier: Identifier) -> DiffEntry {
			if let index = table.index(forKey: identifier) {
				return table[index].value
			}

			let entry = DiffEntry()
			table[identifier] = entry
			return entry
		}

		// Pass 1: Scan the new snapshot.
		for element in current {
			let key = identifier(element)
			let entry = tableEntry(for: key)

			entry.occurenceInNew += 1
			newReferences.append(.table(entry))
		}

		// Pass 2: Scan the old snapshot.
		for (offset, index) in previous.indices.enumerated() {
			let key = identifier(previous[index])
			let entry = tableEntry(for: key)

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

		var changeset = Changeset()

		// Final Pass: Compute diff.
		for position in oldReferences.indices {
			switch oldReferences[position] {
			case .table:
				// Deleted
				changeset.removals.insert(position)

			case let .remote(newPosition):
				let previousIndex = previous.index(previous.startIndex, offsetBy: View.IndexDistance(position))
				let currentIndex = current.index(current.startIndex, offsetBy: View.IndexDistance(newPosition))
				let areEqual = areEqual(previous[previousIndex], current[currentIndex])

				// If the move is only caused by a deletion earlier on, it is still
				// considered in place.
				let isInPlace = newPosition == position || position - newPosition == changeset.removals.count(in: 0 ..< position)

				switch (areEqual, isInPlace) {
				case (false, true):
					changeset.mutations.insert(position)

				case (_, false):
					changeset.moves[newPosition] = Changeset.Move(source: position, isMutated: !areEqual)

				case (true, true):
					break
				}
			}
		}

		for position in newReferences.indices {
			if case .table = newReferences[position] {
				changeset.inserts.insert(position)
			}
		}

		return changeset
	}
}

// FIXME: Swift 4 Associated type constraints
// extension CollectionDiffer {
extension Signal where Value: Collection, Value.Iterator.Element: Collection, Value.Indices.Iterator.Element == Value.Index, Value.Iterator.Element.Indices.Iterator.Element == Value.Iterator.Element.Index {
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
	public func diff<Identifier: Hashable, SectionIdentifier: Hashable>(
		sectionIdentifier: @escaping (Value.Iterator.Element) -> SectionIdentifier,
		areSectionsEqual: @escaping (Value.Iterator.Element, Value.Iterator.Element) -> Bool,
		elementIdentifier: @escaping (Value.Iterator.Element.Iterator.Element) -> Identifier,
		areElementsEqual: @escaping (Value.Iterator.Element.Iterator.Element, Value.Iterator.Element.Iterator.Element) -> Bool
	) -> Signal<Snapshot<Value, SectionedChangeset>, Error> {
		return Signal<Snapshot<Value, SectionedChangeset>, Error> { observer in
			var previous: Value?

			return self.observe { event in
				switch event {
				case let .value(elements):
					let changeset: SectionedChangeset

					if let previous = previous {
						changeset = Value.sectioningDiff(previous: previous,
						                                 current: elements,
						                                 sectionIdentifier: sectionIdentifier,
						                                 areSectionsEqual: areSectionsEqual,
						                                 elementIdentifier: elementIdentifier,
						                                 areElementsEqual: areElementsEqual)
					} else {
						changeset = SectionedChangeset(initial: elements)
					}

					observer.send(value: Snapshot(elements: elements, changeset: changeset))
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

extension SignalProducer where Value: Collection, Value.Iterator.Element: Collection, Value.Indices.Iterator.Element == Value.Index, Value.Iterator.Element.Indices.Iterator.Element == Value.Iterator.Element.Index {
	public func diff<Identifier: Hashable, SectionIdentifier: Hashable>(
		sectionIdentifier: @escaping (Value.Iterator.Element) -> SectionIdentifier,
		areSectionsEqual: @escaping (Value.Iterator.Element, Value.Iterator.Element) -> Bool,
		elementIdentifier: @escaping (Value.Iterator.Element.Iterator.Element) -> Identifier,
		areElementsEqual: @escaping (Value.Iterator.Element.Iterator.Element, Value.Iterator.Element.Iterator.Element) -> Bool
	) -> SignalProducer<Snapshot<Value, SectionedChangeset>, Error> {
		return lift { $0.diff(sectionIdentifier: sectionIdentifier,
		                      areSectionsEqual: areSectionsEqual,
		                      elementIdentifier: elementIdentifier,
		                      areElementsEqual: areElementsEqual) }
	}
}

extension PropertyProtocol where Value: Collection, Value.Iterator.Element: Collection, Value.Indices.Iterator.Element == Value.Index, Value.Iterator.Element.Indices.Iterator.Element == Value.Iterator.Element.Index {
	public func diff<Identifier: Hashable, SectionIdentifier: Hashable>(
		sectionIdentifier: @escaping (Value.Iterator.Element) -> SectionIdentifier,
		areSectionsEqual: @escaping (Value.Iterator.Element, Value.Iterator.Element) -> Bool,
		elementIdentifier: @escaping (Value.Iterator.Element.Iterator.Element) -> Identifier,
		areElementsEqual: @escaping (Value.Iterator.Element.Iterator.Element, Value.Iterator.Element.Iterator.Element) -> Bool
	) -> Property<Snapshot<Value, SectionedChangeset>> {
		return lift { $0.diff(sectionIdentifier: sectionIdentifier,
		                      areSectionsEqual: areSectionsEqual,
		                      elementIdentifier: elementIdentifier,
		                      areElementsEqual: areElementsEqual) }
	}
}

extension Collection where Iterator.Element: Collection, Index == Indices.Iterator.Element, Iterator.Element.Indices.Iterator.Element == Iterator.Element.Index {
	// @testable
	internal static func sectioningDiff<Identifier: Hashable, SectionIdentifier: Hashable>(
		previous: Self,
		current: Self,
		sectionIdentifier: (Iterator.Element) -> SectionIdentifier,
		areSectionsEqual: (Iterator.Element, Iterator.Element) -> Bool,
		elementIdentifier: (Iterator.Element.Iterator.Element) -> Identifier,
		areElementsEqual: (Iterator.Element.Iterator.Element, Iterator.Element.Iterator.Element) -> Bool
	) -> SectionedChangeset {
		var topLevelDiff = diff(previous: previous, current: current, identifier: sectionIdentifier, areEqual: areSectionsEqual)

		let moveDests = IndexSet(topLevelDiff.moves.keys)
		let allInsertions = topLevelDiff.inserts.union(moveDests)
		let moveSources = IndexSet(topLevelDiff.moves.map { $0.value.source })
		let allRemovals = topLevelDiff.removals.union(moveSources)

		var innerDeltas: [Int: SectionedChangeset.MutatedSection] = Dictionary(minimumCapacity: Int(current.count))

		var moves: [Int: Changeset.Move] = [:]
		var mutations = IndexSet()

		for (offset, section) in current.enumerated() {
			guard !topLevelDiff.inserts.contains(offset) else {
				continue
			}

			let predeletionOffset: Int
			let isMove: Bool

			if let move = topLevelDiff.moves[offset] {
				predeletionOffset = move.source
				isMove = true
			} else {
				let preinsertionOffset = offset - allInsertions.count(in: 0 ..< offset)
				predeletionOffset = preinsertionOffset + allRemovals.count(in: 0 ... preinsertionOffset)
				isMove = false
			}

			let previousIndex = previous.index(previous.startIndex, offsetBy: IndexDistance(predeletionOffset))
			let changeset = Iterator.Element.diff(previous: previous[previousIndex],
			                                      current: section,
			                                      identifier: elementIdentifier,
			                                      areEqual: areElementsEqual)

			let representsNoChanges = changeset.representsNoChanges

			if !representsNoChanges {
				innerDeltas[offset] = SectionedChangeset.MutatedSection(changeset: changeset, source: predeletionOffset)
			}

			if isMove {
				moves[offset] = Changeset.Move(source: predeletionOffset, isMutated: !representsNoChanges)
			} else if !representsNoChanges {
				mutations.insert(predeletionOffset)
			}
		}

		topLevelDiff.mutations = mutations
		topLevelDiff.moves = moves

		return SectionedChangeset(sections: topLevelDiff, mutatedSections: innerDeltas)
	}
}

#if !swift(>=3.2)
	extension SignedInteger {
		fileprivate init<I: SignedInteger>(_ integer: I) {
			self.init(integer.toIntMax())
		}
	}
#endif

// Better debugging experience

extension Changeset: CustomDebugStringConvertible {
	public var debugDescription: String {
		func moveDescription(_ destination: Int, _ move: Move) -> String {
			return "\(move.source) -> \(move.isMutated ? "*" : "")\(destination)"
		}

		return ([
			"- inserted \(inserts.count) item(s) at [\(inserts.map(String.init).joined(separator: ", "))]" as String,
			"- deleted \(removals.count) item(s) at [\(removals.map(String.init).joined(separator: ", "))]" as String,
			"- mutated \(mutations.count) item(s) at [\(mutations.map(String.init).joined(separator: ", "))]" as String,
			"- moved \(moves.count) item(s) at [\(moves.map(moveDescription).joined(separator: ", "))]" as String,
		] as [String]).joined(separator: "\n")
	}
}

extension SectionedChangeset: CustomDebugStringConvertible {
	public var debugDescription: String {
		return ([
			sections.debugDescription,
			"- changesets of mutated sections: <<<" as String,
			mutatedSections.map { offset, section in
				"    section \(section.source) -> \(offset)\n" + section.changeset.debugDescription._split(separator: "\n").map { "    \($0)" }.joined(separator: "\n")
			}.joined(separator: "\n") as String,
			"  >>>" as String,
		] as [String]).joined(separator: "\n")
	}
}
