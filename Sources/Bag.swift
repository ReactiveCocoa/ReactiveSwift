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
	public struct Token: Sendable {
		fileprivate let value: UInt64
	}

	fileprivate var elements: ContiguousArray<Element>
	fileprivate var tokens: ContiguousArray<UInt64>

	private var nextToken: Token

	public init() {
		elements = ContiguousArray()
		tokens = ContiguousArray()
		nextToken = Token(value: 0)
	}

	public init<S: Sequence>(_ elements: S) where S.Iterator.Element == Element {
		self.elements = ContiguousArray(elements)
		self.nextToken = Token(value: UInt64(self.elements.count))
		self.tokens = ContiguousArray(0..<nextToken.value)
	}

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
		nextToken = Token(value: token.value &+ 1)

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
		// Given that tokens are always added to the end of the array and have a monotonically
		// increasing value, this list is always sorted, so we can use a binary search to improve
		// performance if this list gets large.
		guard let index = binarySearch(tokens, value: token.value) else {
			return nil
		}

		tokens.remove(at: index)
		return elements.remove(at: index)
	}

	/// Perform a binary search on a sorted array returning the index of a value.
	///
	/// - parameters:
	///   - input: The sorted array to search for `value`
	///   - value: The value to find in the sorted `input` array
	///
	/// - returns: The index of the `value` or `nil`
	private func binarySearch(_ input:ContiguousArray<UInt64>, value: UInt64) -> Int? {
		var lower = 0
		var upper = input.count - 1

		while (true) {
			let current = (lower + upper)/2
			if(input[current] == value) {
				return current
			}
			
			if (lower > upper) {
				return nil
			}
			
			if (input[current] > value) {
				upper = current - 1
			} else {
				lower = current + 1
			}
		}
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
		return Iterator(elements.makeIterator())
	}

	/// An iterator of `Bag`.
	public struct Iterator: IteratorProtocol {
		private var base: ContiguousArray<Element>.Iterator

		fileprivate init(_ base: ContiguousArray<Element>.Iterator) {
			self.base = base
		}

		public mutating func next() -> Element? {
			return base.next()
		}
	}
}

extension Bag: Sendable where Element: Sendable {}
