import Nimble
import Quick
import ReactiveSwift
import Result
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin.C
#endif

private struct OpaqueValue: Equatable {
	let value: Int

	init(_ value: Int) {
		self.value = value
	}

	static func ==(left: OpaqueValue, right: OpaqueValue) -> Bool {
		return left.value == right.value
	}
}

private class ObjectValue {}

class CollectionDiffingSpec: QuickSpec {
	override func spec() {
		describe("diff()") {
			describe("Equatable elements") {
				it("should produce a delta that can reproduce the current snapshot from the previous snapshot") {
					let (snapshots, snapshotObserver) = Signal<[OpaqueValue], NoError>.pipe()
					let deltas = snapshots.diff()

					let oldValues = Array(0 ..< 32).map(OpaqueValue.init).shuffled()
					let newValues = Array(oldValues.dropLast(8) + (128 ..< 168).map(OpaqueValue.init)).shuffled()

					var delta: CollectionDelta<[OpaqueValue]>?
					deltas.observeValues { delta = $0 }
					expect(delta).to(beNil())

					snapshotObserver.send(value: oldValues)
					expect(delta).toNot(beNil())
					expect(delta?.previous).to(beNil())

					snapshotObserver.send(value: newValues)
					expect(delta).toNot(beNil())
					expect(delta?.previous).toNot(beNil())

					if let delta = delta, let previous = delta.previous {
						var values = previous
						expect(values) == oldValues

						delta.removals
							.union(IndexSet(delta.moves.lazy.map { $0.previous }))
							.reversed()
							.forEach { values.remove(at: $0) }

						delta.mutations.forEach { values[$0] = delta.current[$0] }

						delta.inserts
							.union(IndexSet(delta.moves.lazy.map { $0.current }))
							.forEach { values.insert(delta.current[$0], at: $0) }

						expect(values) == newValues
					}
				}
			}

			describe("Hashable elements") {
				it("should produce a delta that can reproduce the current snapshot from the previous snapshot") {
					let (snapshots, snapshotObserver) = Signal<[Int], NoError>.pipe()
					let deltas = snapshots.diff()

					let oldNumbers = Array(0 ..< 32).shuffled()
					let newNumbers = Array(oldNumbers.dropLast(8) + (128 ..< 168)).shuffled()

					var delta: CollectionDelta<[Int]>?
					deltas.observeValues { delta = $0 }
					expect(delta).to(beNil())

					snapshotObserver.send(value: oldNumbers)
					expect(delta).toNot(beNil())
					expect(delta?.previous).to(beNil())

					snapshotObserver.send(value: newNumbers)
					expect(delta).toNot(beNil())
					expect(delta?.previous).toNot(beNil())

					if let delta = delta, let previous = delta.previous {
						var numbers = previous
						expect(numbers) == oldNumbers

						delta.removals
							.union(IndexSet(delta.moves.lazy.map { $0.previous }))
							.reversed()
							.forEach { numbers.remove(at: $0) }

						delta.mutations.forEach { numbers[$0] = delta.current[$0] }

						delta.inserts
							.union(IndexSet(delta.moves.lazy.map { $0.current }))
							.forEach { numbers.insert(delta.current[$0], at: $0) }

						expect(numbers) == newNumbers
					}
				}

				it("should produce a delta that can reproduce the current snapshot from the previous snapshot, even if the collection is bidirectional") {
					let (snapshots, snapshotObserver) = Signal<String.CharacterView, NoError>.pipe()
					let deltas = snapshots.diff()

					let oldCharacters = "abcdefghijkl12345@".characters.shuffled()
					var newCharacters = oldCharacters.dropLast(8)
					newCharacters.append(contentsOf: "mnopqrstuvwxyz67890#".characters)
					newCharacters = newCharacters.shuffled()

					var delta: CollectionDelta<String.CharacterView>?
					deltas.observeValues { delta = $0 }
					expect(delta).to(beNil())

					snapshotObserver.send(value: oldCharacters)
					expect(delta).toNot(beNil())
					expect(delta?.previous).to(beNil())

					snapshotObserver.send(value: newCharacters)
					expect(delta).toNot(beNil())
					expect(delta?.previous).toNot(beNil())

					if let delta = delta, let previous = delta.previous {
						var characters = previous
						expect(characters.elementsEqual(oldCharacters)) == true

						delta.removals
							.union(IndexSet(delta.moves.lazy.map { $0.previous }))
							.reversed()
							.forEach { offset in
								let index = characters.index(characters.startIndex, offsetBy: offset)
								characters.remove(at: index)
							}

						delta.mutations.forEach { offset in
							let index = characters.index(characters.startIndex, offsetBy: offset)
							let index2 = delta.current.index(delta.current.startIndex, offsetBy: offset)
							characters.replaceSubrange(index ..< characters.index(after: index),
													   with: CollectionOfOne(delta.current[index2]))
						}

						delta.inserts
							.union(IndexSet(delta.moves.lazy.map { $0.current }))
							.forEach { offset in
								let index = characters.index(characters.startIndex, offsetBy: offset)
								let index2 = delta.current.index(delta.current.startIndex, offsetBy: offset)
								characters.insert(delta.current[index2], at: index)
							}

						expect(characters.elementsEqual(newCharacters)) == true
					}
				}
			}

			describe("AnyObject elements") {
				it("should produce a delta that can reproduce the current snapshot from the previous snapshot") {
					let (snapshots, snapshotObserver) = Signal<[ObjectValue], NoError>.pipe()
					let deltas = snapshots.diff()

					let oldObjects = Array(0 ..< 32).map { _ in ObjectValue() }.shuffled()
					let newObjects = Array(oldObjects.dropLast(8) + (0 ..< 32).map { _ in ObjectValue() }).shuffled()

					var delta: CollectionDelta<[ObjectValue]>?
					deltas.observeValues { delta = $0 }
					expect(delta).to(beNil())

					snapshotObserver.send(value: oldObjects)
					expect(delta).toNot(beNil())
					expect(delta?.previous).to(beNil())

					snapshotObserver.send(value: newObjects)
					expect(delta).toNot(beNil())
					expect(delta?.previous).toNot(beNil())

					if let delta = delta, let previous = delta.previous {
						var objects = previous
						expect(objects.elementsEqual(oldObjects, by: ===)) == true

						delta.removals
							.union(IndexSet(delta.moves.lazy.map { $0.previous }))
							.reversed()
							.forEach { objects.remove(at: $0) }

						delta.mutations.forEach { objects[$0] = delta.current[$0] }

						delta.inserts
							.union(IndexSet(delta.moves.lazy.map { $0.current }))
							.forEach { objects.insert(delta.current[$0], at: $0) }

						expect(objects.elementsEqual(newObjects, by: ===)) == true
					}
				}
			}
		}
	}
}

private extension RangeReplaceableCollection where Index == Indices.Iterator.Element {
	func shuffled() -> Self {
		var elements = self

		for i in 0 ..< Int(elements.count) {
			let distance = randomInteger() % Int(elements.count)
			let random = elements.index(elements.startIndex, offsetBy: IndexDistance(distance))
			let index = elements.index(elements.startIndex, offsetBy: IndexDistance(i))
			guard random != index else { continue }

			let temp = elements[index]
			elements.replaceSubrange(index ..< elements.index(after: index), with: CollectionOfOne(elements[random]))
			elements.replaceSubrange(random ..< elements.index(after: random), with: CollectionOfOne(temp))
		}

		return elements
	}
}

#if !swift(>=3.2)
	extension SignedInteger {
		fileprivate init<I: SignedInteger>(_ integer: I) {
			self.init(integer.toIntMax())
		}
	}
#endif

#if os(Linux)
	private func randomInteger() -> Int {
		srandom(UInt32(time(nil)))
		return Int(random() >> 1)
	}
#else
	private func randomInteger() -> Int {
		return Int(arc4random() >> 1)
	}
#endif
