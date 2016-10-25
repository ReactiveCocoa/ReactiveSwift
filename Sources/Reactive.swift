/// Describes a provider of reactive extensions.
///
/// - note: `ReactiveExtensionsProvider` does not indicate whether a type is
///         reactive. It is intended for extensions to types that are not owned
///         by the module in order to avoid name collisions and return type
///         ambiguities.
public protocol ReactiveExtensionsProvider: class {}

extension ReactiveExtensionsProvider {
	/// A proxy which hosts reactive extensions for `self`.
	public var reactive: Reactive<Self> {
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
