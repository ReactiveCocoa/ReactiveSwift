//
//  TestError.swift
//  ReactiveSwift
//
//  Created by Almas Sapargali on 1/26/15.
//  Copyright (c) 2015 GitHub. All rights reserved.
//

import ReactiveSwift
import Result

internal enum TestError: Int {
	case `default` = 0
	case error1 = 1
	case error2 = 2
}

extension TestError: Error {
}

internal extension SignalProducer {
	/// Halts if an error is emitted in the receiver signal.
	/// This is useful in tests to be able to just use `startWithNext`
	/// in cases where we know that an error won't be emitted.
	func assumeNevers() -> SignalProducer<Value, Never> {
		return self.lift { $0.assumeNevers() }
	}
}

internal extension Signal {
	/// Halts if an error is emitted in the receiver signal.
	/// This is useful in tests to be able to just use `startWithNext`
	/// in cases where we know that an error won't be emitted.
	func assumeNevers() -> Signal<Value, Never> {
		return self.mapError { error in
			fatalError("Unexpected error: \(error)")

			()
		}
	}
}
