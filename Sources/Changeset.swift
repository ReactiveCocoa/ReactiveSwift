import Foundation

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

	public init() {}

	public init<C: Collection>(initial: C) {
		inserts = IndexSet(integersIn: 0 ..< Int(initial.count))
	}

	public init<C: Collection, Identifier: Hashable>(
		previous: C,
		current: C,
		identifier: (C.Iterator.Element) -> Identifier,
		areEqual: (C.Iterator.Element, C.Iterator.Element) -> Bool
	) where C.Index == C.Indices.Iterator.Element {
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

		self.init()

		// Final Pass: Compute diff.
		for position in oldReferences.indices {
			switch oldReferences[position] {
			case .table:
				// Deleted
				removals.insert(position)

			case let .remote(newPosition):
				let previousIndex = previous.index(previous.startIndex, offsetBy: C.IndexDistance(position))
				let currentIndex = current.index(current.startIndex, offsetBy: C.IndexDistance(newPosition))
				let areEqual = areEqual(previous[previousIndex], current[currentIndex])

				// If the move is only caused by a deletion earlier on, it is still
				// considered in place.
				let isInPlace = newPosition == position || position - newPosition == removals.count(in: 0 ..< position)

				switch (areEqual, isInPlace) {
				case (false, true):
					mutations.insert(position)

				case (_, false):
					moves[newPosition] = Changeset.Move(source: position, isMutated: !areEqual)

				case (true, true):
					break
				}
			}
		}

		for position in newReferences.indices {
			if case .table = newReferences[position] {
				inserts.insert(position)
			}
		}
	}
}

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

#if !swift(>=3.2)
	extension SignedInteger {
		fileprivate init<I: SignedInteger>(_ integer: I) {
			self.init(integer.toIntMax())
		}
	}
#endif
