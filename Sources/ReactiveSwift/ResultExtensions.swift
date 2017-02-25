import Result

/// Private alias of the free `materialize()` from `Result`.
///
/// This exists because within a `Signal` or `SignalProducer` operator,
/// `materialize()` refers to the operator with that name.
/// Namespacing as `Result.materialize()` doesn't work either,
/// because it tries to resolve a static member on the _type_
/// `Result`, rather than the free function in the _module_
/// of the same name.
internal func materialize<T>(_ f: () throws -> T) -> Result<T, AnyError> {
	return materialize(try f())
}
