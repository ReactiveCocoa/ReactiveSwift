//
//  Bag.swift
//  ReactiveSwift
//
//  Created by Justin Spahr-Summers on 2014-07-10.
//  Copyright (c) 2014 GitHub. All rights reserved.
//

/// A uniquely identifying token for removing a value that was inserted into a
/// Bag.
public final class RemovalToken {}

/// An unordered, non-unique collection of values of type `Element`.
public struct Bag<Element> {
	fileprivate var elements: ContiguousArray<BagElement<Element>> = []

	public init() {}

	/// Insert the given value into `self`, and return a token that can
	/// later be passed to `remove(using:)`.
	///
	/// - parameters:
	///   - value: A value that will be inserted.
	@discardableResult
	public mutating func insert(_ value: Element) -> RemovalToken {
		let token = RemovalToken()
		let element = BagElement(value: value, token: token)

		elements.append(element)
		return token
	}

	/// Remove a value, given the token returned from `insert()`.
	///
	/// - note: If the value has already been removed, nothing happens.
	///
	/// - parameters:
	///   - token: A token returned from a call to `insert()`.
	public mutating func remove(using token: RemovalToken) {
		let tokenIdentifier = ObjectIdentifier(token)
		// Removal is more likely for recent objects than old ones.
		for i in elements.indices.reversed() {
			if ObjectIdentifier(elements[i].token) == tokenIdentifier {
				elements.remove(at: i)
				break
			}
		}
	}
}

extension Bag: Collection {
	public typealias Index = Array<Element>.Index

	public var startIndex: Index {
		return elements.startIndex
	}
	
	public var endIndex: Index {
		return elements.endIndex
	}

	public subscript(index: Index) -> Element {
		return elements[index].value
	}

	public func index(after i: Index) -> Index {
		return i + 1
	}

	public func makeIterator() -> BagIterator<Element> {
		return BagIterator(elements)
	}
}

private struct BagElement<Value> {
	let value: Value
	let token: RemovalToken
}

extension BagElement: CustomStringConvertible {
	var description: String {
		return "BagElement(\(value))"
	}
}

/// An iterator of `Bag`.
public struct BagIterator<Element>: IteratorProtocol {
	private let base: ContiguousArray<BagElement<Element>>
	private var nextIndex: Int
	private let endIndex: Int

	fileprivate init(_ base: ContiguousArray<BagElement<Element>>) {
		self.base = base
		nextIndex = base.startIndex
		endIndex = base.endIndex
	}

	public mutating func next() -> Element? {
		let currentIndex = nextIndex

		if currentIndex < endIndex {
			nextIndex = currentIndex + 1
			return base[currentIndex].value
		}

		return nil
	}
}
