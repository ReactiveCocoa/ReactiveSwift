public func weakify<Target: AnyObject, A>(
	_ target: Target,
	_ transform: @escaping (Target) -> (A) -> Void
) -> (A) -> Void {
	return { [weak target] a in
		target.map(transform)?(a)
	}
}

public func weakify<Target: AnyObject, A, B>(
	_ target: Target,
	_ transform: @escaping (Target) -> (A, B) -> Void
	) -> (A, B) -> Void {
	return { [weak target] a, b in
		target.map(transform)?(a, b)
	}
}

public func weakify<Target: AnyObject, A, B, C>(
	_ target: Target,
	_ transform: @escaping (Target) -> (A, B, C) -> Void
	) -> (A, B, C) -> Void {
	return { [weak target] a, b, c in
		target.map(transform)?(a, b, c)
	}
}

public func weakify<Target: AnyObject, A, B, C, D>(
	_ target: Target,
	_ transform: @escaping (Target) -> (A, B, C, D) -> Void
	) -> (A, B, C, D) -> Void {
	return { [weak target] a, b, c, d in
		target.map(transform)?(a, b, c, d)
	}
}

public func weakify<Target: AnyObject, A, B, C, D, E>(
	_ target: Target,
	_ transform: @escaping (Target) -> (A, B, C, D, E) -> Void
	) -> (A, B, C, D, E) -> Void {
	return { [weak target] a, b, c, d, e in
		target.map(transform)?(a, b, c, d, e)
	}
}

public func weakify<Target: AnyObject, A, B, C, D, E, F>(
	_ target: Target,
	_ transform: @escaping (Target) -> (A, B, C, D, E, F) -> Void
	) -> (A, B, C, D, E, F) -> Void {
	return { [weak target] a, b, c, d, e, f in
		target.map(transform)?(a, b, c, d, e, f)
	}
}
