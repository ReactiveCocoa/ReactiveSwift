//
//  Lifecycle.swift
//  ReactiveSwift
//
//  Created by Andrew Arnopoulos on 9/9/18.
//  Copyright © 2018 GitHub. All rights reserved.
//

import Foundation

public class Lifecycle {

	/// Hook that can be used to get the current lifetime.
	///
	/// - note: The consumer of `Lifecycle` is responsible for checking
	///         whether or not the lifetime is valid.
	public let lifetime: Property<Lifetime>
	private let lock: LockProtocol
	private var token: Lifetime.Token?
	private let mutableLifetime: MutableProperty<Lifetime>

	/// Initializes a new `Lifecycle`
	///
	/// - parameters:
	///   - invalidate: A flag used to determine whether the current
	///                 lifetime is invalidated.
	public init(invalidate: Bool = false) {
		let (lifetime, token) = Lifetime.make()
		self.token = (!invalidate) ? token : nil
		mutableLifetime = MutableProperty(lifetime)
		self.lifetime = Property(mutableLifetime)
		lock = Lock.PthreadLock(recursive: true)
	}

	/// Initializer used for testing purposes
	///
	/// - parameters:
	///   - lock: A lock that can be used to reproduce race conditions reliably.
	internal init(lock: LockProtocol) {
		let (lifetime, token) = Lifetime.make()
		self.token = token
		mutableLifetime = MutableProperty(lifetime)
		self.lifetime = Property(mutableLifetime)
		self.lock = lock
	}

	/// Updates lifetime property and invalidates current lifetime.
	public func update() {
		lock.perform { [weak self] in
			self?.unsafeUpdate()
		}
	}

	/// Updates lifetime property and invalidates cuurent lifetime
	/// if current lifetime is valid.
	///
	/// - note: If the current lifetime is invalid nothing happens.
	public func updateIfValid() {
		lock.perform { [weak self] in
			if self?.token != nil {
				self?.unsafeUpdate()
			}
		}
	}

	/// Invalidates lifetime property.
	///
	/// - note: If the current lifetime is invalid nothing happens.
	public func invalidate() {
		lock.perform { [weak self] in
			self?.token = nil
		}
	}

	private func unsafeUpdate() {
		let (lifetime, token) = Lifetime.make()
		self.token = token
		mutableLifetime.value = lifetime
	}

}
