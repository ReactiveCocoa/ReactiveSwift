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

private class ObjectValue {}

class CollectionDiffingSpec: QuickSpec {
	override func spec() {
		describe("diff()") {
			describe("Hashable elements") {
				it("should produce a snapshot that can be reproduced from the previous snapshot by applying the changeset") {
					let (snapshots, snapshotObserver) = Signal<[Int], NoError>.pipe()
					let deltas = snapshots.diff()

					let oldNumbers = Array(0 ..< 32).shuffled()
					let newNumbers = Array(oldNumbers.dropLast(8) + (128 ..< 168)).shuffled()

					var snapshot: Snapshot<[Int], Changeset>?

					deltas.observeValues {
						snapshot = $0
					}
					expect(snapshot).to(beNil())

					snapshotObserver.send(value: oldNumbers)
					expect(snapshot).toNot(beNil())
					expect(snapshot?.previous).to(beNil())

					snapshotObserver.send(value: newNumbers)
					expect(snapshot).toNot(beNil())
					expect(snapshot?.previous).toNot(beNil())

					if let snapshot = snapshot, let previous = snapshot.previous {
						var numbers = previous
						expect(numbers) == oldNumbers

						snapshot.changeset.removals
							.union(IndexSet(snapshot.changeset.moves.values.lazy.map { $0.source }))
							.reversed()
							.forEach { numbers.remove(at: $0) }

						snapshot.changeset.mutations.forEach { numbers[$0] = snapshot.current[$0] }

						snapshot.changeset.inserts
							.union(IndexSet(snapshot.changeset.moves.keys))
							.forEach { numbers.insert(snapshot.current[$0], at: $0) }

						expect(numbers) == newNumbers
					}
				}

				it("should produce a snapshot that can be reproduced from the previous snapshot by applying the changeset, even if the collection is bidirectional") {
					let (snapshots, snapshotObserver) = Signal<String.CharacterView, NoError>.pipe()
					let deltas = snapshots.diff()

					let oldCharacters = "abcdefghijkl12345@".characters.shuffled()
					var newCharacters = oldCharacters.dropLast(8)
					newCharacters.append(contentsOf: "mnopqrstuvwxyz67890#".characters)
					newCharacters = newCharacters.shuffled()

					var snapshot: Snapshot<String.CharacterView, Changeset>?

					deltas.observeValues {
						snapshot = $0
					}
					expect(snapshot).to(beNil())

					snapshotObserver.send(value: oldCharacters)
					expect(snapshot).toNot(beNil())
					expect(snapshot?.previous).to(beNil())

					snapshotObserver.send(value: newCharacters)
					expect(snapshot).toNot(beNil())
					expect(snapshot?.previous).toNot(beNil())

					if let snapshot = snapshot, let previous = snapshot.previous {
						var characters = previous
						expect(characters.elementsEqual(oldCharacters)) == true

						snapshot.changeset.removals
							.union(IndexSet(snapshot.changeset.moves.values.lazy.map { $0.source }))
							.reversed()
							.forEach { offset in
								let index = characters.index(characters.startIndex, offsetBy: offset)
								characters.remove(at: index)
							}

						snapshot.changeset.mutations.forEach { offset in
							let index = characters.index(characters.startIndex, offsetBy: offset)
							let index2 = snapshot.current.index(snapshot.current.startIndex, offsetBy: offset)
							characters.replaceSubrange(index ..< characters.index(after: index),
													   with: CollectionOfOne(snapshot.current[index2]))
						}

						snapshot.changeset.inserts
							.union(IndexSet(snapshot.changeset.moves.keys))
							.forEach { offset in
								let index = characters.index(characters.startIndex, offsetBy: offset)
								let index2 = snapshot.current.index(snapshot.current.startIndex, offsetBy: offset)
								characters.insert(snapshot.current[index2], at: index)
							}

						expect(characters.elementsEqual(newCharacters)) == true
					}
				}
			}

			describe("AnyObject elements") {
				it("should produce a snapshot that can be reproduced from the previous snapshot by applying the changeset") {
					let (snapshots, snapshotObserver) = Signal<[ObjectValue], NoError>.pipe()
					let deltas = snapshots.diff()

					let oldObjects = Array(0 ..< 32).map { _ in ObjectValue() }.shuffled()
					let newObjects = Array(oldObjects.dropLast(8) + (0 ..< 32).map { _ in ObjectValue() }).shuffled()

					var snapshot: Snapshot<[ObjectValue], Changeset>?

					deltas.observeValues {
						snapshot = $0
					}
					expect(snapshot).to(beNil())

					snapshotObserver.send(value: oldObjects)
					expect(snapshot).toNot(beNil())
					expect(snapshot?.previous).to(beNil())

					snapshotObserver.send(value: newObjects)
					expect(snapshot).toNot(beNil())
					expect(snapshot?.previous).toNot(beNil())

					if let snapshot = snapshot, let previous = snapshot.previous {
						var objects = previous
						expect(objects.elementsEqual(oldObjects, by: ===)) == true

						snapshot.changeset.removals
							.union(IndexSet(snapshot.changeset.moves.values.lazy.map { $0.source }))
							.reversed()
							.forEach { objects.remove(at: $0) }

						snapshot.changeset.mutations.forEach { objects[$0] = snapshot.current[$0] }

						snapshot.changeset.inserts
							.union(IndexSet(snapshot.changeset.moves.keys))
							.forEach { objects.insert(snapshot.current[$0], at: $0) }

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
