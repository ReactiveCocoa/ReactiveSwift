//
//  MockLock.swift
//  ReactiveSwift
//
//  Created by Andrew Arnopoulos on 9/9/18.
//  Copyright © 2018 GitHub. All rights reserved.
//

import Foundation
@testable import ReactiveSwift

class MockLock: LockProtocol {
	var lockCount = 0
	var unlockCount = 0
	var deadlock = false
	func lock() {
		lockCount += 1
		if lockCount - unlockCount > 1 {
			deadlock = true
		}
	}

	func unlock() {
		unlockCount += 1
	}

	func `try`() -> Bool {
		fatalError("Not yet implemented")
	}
}
