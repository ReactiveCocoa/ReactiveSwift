/// Represents a snapshot of a collection.
///
/// The changeset associated with the first snapshot received by any given observation
/// is generally irrelevant. Observations should special case the first snapshot as a
/// complete replacement, or whatever semantic that fits their purpose.
///
/// The previous version of the collection is unavailable on the initial snapshot,
/// since there is no history to refer to.
///
/// While the snapshot does not bind the `Changeset` associated type with any constraint,
/// it is expected to be either a `Changeset`, or a composite of `Changeset`s for a nested
/// collection.
public struct Snapshot<Collection: Swift.Collection, Changeset>: SnapshotProtocol {
	/// The previous version of the collection, or `nil` if `self` is an initial snapshot.
	public let previous: Collection?

	/// The current version of the collection.
	public let current: Collection

	/// The changeset which, when applied on `previous`, reproduces `current`.
	public let changeset: Changeset

	/// Create a snapshot.
	///
	/// - paramaters:
	///   - previous: The previous version of the collection.
	///   - current: The current version of the collection.
	///   - changeset: The changeset which, when applied on `previous`, reproduces
	///                `current`.
	public init(previous: Collection?, current: Collection, changeset: Changeset) {
		(self.previous, self.current, self.changeset) = (previous, current, changeset)
	}
}

/// A protocol for constraining associated types to a `Snapshot`.
public protocol SnapshotProtocol {
	associatedtype Collection: Swift.Collection
	associatedtype Changeset

	var previous: Collection? { get }
	var current: Collection { get }
	var changeset: Changeset { get }
}
