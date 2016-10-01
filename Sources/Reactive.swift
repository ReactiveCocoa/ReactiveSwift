/// Describes a class which has been extended with reactive elements.
///
/// - note: `ExtendedForReactiveness` is only intended for extensions to types
///         that are not owned by the module. Non-conforming types may carry
///         first-party reactive elements.
public protocol ExtendedForReactiveness: class {}

extension ExtendedForReactiveness {
	/// A proxy which exposes the reactivity of `self`.
	public var rac: Reactive<Self> {
		return Reactive(self)
	}
}

// A `Reactive` proxy hosts reactive extensions to `Base`.
public struct Reactive<Base> {
	public let base: Base

	// Construct a proxy.
	//
	// - parameters:
	//   - base: The object to be proxied.
	fileprivate init(_ base: Base) {
		self.base = base
	}
}
