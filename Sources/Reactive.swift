/// Describes a provider of reactive extensions.
///
/// - note: `ReactiveExtensionsProvider` does not indicate whether a type is
///         reactive. It is intended for extensions to types that do not own by
///         the module so as to avoid name collision and return type ambiguity.
public protocol ReactiveExtensionsProvider: class {}

extension ReactiveExtensionsProvider {
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
