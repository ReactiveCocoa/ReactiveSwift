//
//  Bag.swift
//  ReactiveSwift
//
//  Created by Justin Spahr-Summers on 2014-07-10.
//  Copyright (c) 2014 GitHub. All rights reserved.
//

/// An unordered, non-unique collection of values of type `Element`.
public struct Bag<Element> {
	/// A uniquely identifying token for removing a value that was inserted into a
	/// Bag.
	public struct Token {
		fileprivate let value: UInt64
	}

	fileprivate var elements: ContiguousArray<Element> = []
	fileprivate var tokens: ContiguousArray<UInt64> = []

	private var nextToken: Token = Token(value: 0)

	public init() {}

	/// Insert the given value into `self`, and return a token that can
	/// later be passed to `remove(using:)`.
	///
	/// - parameters:
	///   - value: A value that will be inserted.
	@discardableResult
	public mutating func insert(_ value: Element) -> Token {
		let token = nextToken

		// Practically speaking, this would overflow only if we have 101% uptime and we
		// manage to call `insert(_:)` every 1 ns for 500+ years non-stop.
		nextToken = Token(value: token.value + 1)

		elements.append(value)
		tokens.append(token.value)

		return token
	}

	/// Remove a value, given the token returned from `insert()`.
	///
	/// - note: If the value has already been removed, nothing happens.
	///
	/// - parameters:
	///   - token: A token returned from a call to `insert()`.
	@discardableResult
	public mutating func remove(using token: Token) -> Element? {
		for i in elements.indices.reversed() {
			if tokens[i] == token.value {
				tokens.remove(at: i)
				return elements.remove(at: i)
			}
		}

		return nil
	}
}

extension Bag: RandomAccessCollection {
	public var startIndex: Int {
		return elements.startIndex
	}

	public var endIndex: Int {
		return elements.endIndex
	}

	public subscript(index: Int) -> Element {
		return elements[index]
	}

	public func makeIterator() -> Iterator {
		return Iterator(elements)
	}

	/// An iterator of `Bag`.
	public struct Iterator: IteratorProtocol {
		private let base: ContiguousArray<Element>
		private var nextIndex: Int
		private let endIndex: Int

		fileprivate init(_ base: ContiguousArray<Element>) {
			self.base = base
			nextIndex = base.startIndex
			endIndex = base.endIndex
		}

		public mutating func next() -> Element? {
			let currentIndex = nextIndex

			if currentIndex < endIndex {
				nextIndex = currentIndex + 1
				return base[currentIndex]
			}

			return nil
		}
	}
}
