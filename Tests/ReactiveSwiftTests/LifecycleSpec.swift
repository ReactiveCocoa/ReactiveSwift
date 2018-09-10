//
//  LifecycleSpec.swift
//  ReactiveSwift
//
//  Created by Andrew Arnopoulos on 9/9/18.
//  Copyright © 2018 GitHub. All rights reserved.
//

import Foundation
import Quick
import Nimble
@testable import ReactiveSwift

final class LifecycleSpec: QuickSpec {
	override func spec() {
		describe("Lifecycle") {
			it("should invalidate lifetime when invalidate is called") {
				let cycle = Lifecycle()
				let lifetime = cycle.lifetime.value
				cycle.invalidate()
				expect(lifetime.hasEnded) == true
			}

			it("should update lifetime when update is called") {
				let cycle = Lifecycle()
				let lifetime = cycle.lifetime.value
				cycle.update()
				expect(cycle.lifetime.value).toNot(be(lifetime))
				expect(lifetime.hasEnded) == true
			}

			it("should guarantee mutual exclusion when calling update") {
				let lock = MockLock()
				let cycle = Lifecycle(lock: lock)
				cycle.update()
				expect(lock.lockCount) == 1
				expect(lock.unlockCount) == 1
			}

			it("should guarantee mutual exclusion when calling invalidate") {
				let lock = MockLock()
				let cycle = Lifecycle(lock: lock)
				cycle.invalidate()
				expect(lock.lockCount) == 1
				expect(lock.unlockCount) == 1
			}

			it("should guarantee mutual exclusion when calling mutually exclusive functions") {
				let lock = MockLock()
				let cycle = Lifecycle(lock: lock)
				cycle.update()
				cycle.updateIfValid()
				cycle.invalidate()
				expect(lock.lockCount) == 3
				expect(lock.unlockCount) == 3
			}

			it("should not deadlock when updateIfValid is called") {
				let lock = MockLock()
				let cycle = Lifecycle(lock: lock)
				cycle.updateIfValid()
				expect(lock.deadlock) == false
			}

			it("should update if lifetime is valid when updateIfValid is called") {
				let cycle = Lifecycle()
				let lifetime = cycle.lifetime.value
				cycle.updateIfValid()
				expect(cycle.lifetime.value).notTo(be(lifetime))
			}

			it("should not update if lifetime is invalid when updateIfValid is called") {
				let cycle = Lifecycle()
				let lifetime = cycle.lifetime.value
				cycle.invalidate()
				cycle.updateIfValid()
				expect(cycle.lifetime.value).to(be(lifetime))
			}
		}
	}
}
