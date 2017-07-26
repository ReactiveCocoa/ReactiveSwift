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
