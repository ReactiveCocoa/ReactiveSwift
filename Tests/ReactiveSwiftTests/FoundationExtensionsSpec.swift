//
//  FoundationExtensionsSpec.swift
//  ReactiveSwift
//
//  Created by Neil Pankey on 5/22/15.
//  Copyright (c) 2015 GitHub. All rights reserved.
//

import Foundation
import Dispatch
import Result
import Nimble
import Quick
@testable import ReactiveSwift

extension Notification.Name {
	static let racFirst = Notification.Name(rawValue: "rac_notifications_test")
	static let racAnother = Notification.Name(rawValue: "rac_notifications_another")
}

class FoundationExtensionsSpec: QuickSpec {
	override func spec() {
		describe("NotificationCenter.reactive.notifications") {
			let center = NotificationCenter.default

			it("should send notifications on the signal") {
				let signal = center.reactive.notifications(forName: .racFirst)

				var notif: Notification? = nil
				let disposable = signal.observeValues { notif = $0 }

				center.post(name: .racAnother, object: nil)
				expect(notif).to(beNil())

				center.post(name: .racFirst, object: nil)
				expect(notif?.name) == .racFirst

				notif = nil
				disposable?.dispose()

				center.post(name: .racFirst, object: nil)
				expect(notif).to(beNil())
			}

			it("should be freed if it is not reachable and no observer is attached") {
				weak var signal: Signal<Notification, NoError>?
				var isDisposed = false

				let disposable: Disposable? = {
					let innerSignal = center.reactive.notifications(forName: nil)
						.on(disposed: { isDisposed = true })

					signal = innerSignal
					return innerSignal.observe { _ in }
				}()

				expect(isDisposed) == false
				expect(signal).toNot(beNil())

				disposable?.dispose()

				expect(isDisposed) == true
				expect(signal).to(beNil())
			}

			it("should be not freed if it still has one or more active observers") {
				weak var signal: Signal<Notification, NoError>?
				var isDisposed = false

				let disposable: Disposable? = {
					let innerSignal = center.reactive.notifications(forName: nil)
						.on(disposed: { isDisposed = true })

					signal = innerSignal
					innerSignal.observe { _ in }
					return innerSignal.observe { _ in }
				}()

				expect(isDisposed) == false
				expect(signal).toNot(beNil())

				disposable?.dispose()

				expect(isDisposed) == false
				expect(signal).toNot(beNil())
			}
		}

		describe("DispatchTimeInterval") {
			it("should scale time values as expected") {
				expect((DispatchTimeInterval.seconds(1) * 0.1).timeInterval).to(beCloseTo(DispatchTimeInterval.milliseconds(100).timeInterval))
				expect((DispatchTimeInterval.milliseconds(100) * 0.1).timeInterval).to(beCloseTo(DispatchTimeInterval.microseconds(10000).timeInterval))

				expect((DispatchTimeInterval.seconds(5) * 0.5).timeInterval).to(beCloseTo(DispatchTimeInterval.milliseconds(2500).timeInterval))
				expect((DispatchTimeInterval.seconds(1) * 0.25).timeInterval).to(beCloseTo(DispatchTimeInterval.milliseconds(250).timeInterval))
			}

			it("should produce the expected TimeInterval values") {
				expect(DispatchTimeInterval.seconds(1).timeInterval).to(beCloseTo(1.0))
				expect(DispatchTimeInterval.milliseconds(1).timeInterval).to(beCloseTo(0.001))
				expect(DispatchTimeInterval.microseconds(1).timeInterval).to(beCloseTo(0.000001, within: 0.0000001))
				expect(DispatchTimeInterval.nanoseconds(1).timeInterval).to(beCloseTo(0.000000001, within: 0.0000000001))

				expect(DispatchTimeInterval.milliseconds(500).timeInterval).to(beCloseTo(0.5))
				expect(DispatchTimeInterval.milliseconds(250).timeInterval).to(beCloseTo(0.25))
				#if swift(>=3.2)
					expect(DispatchTimeInterval.never.timeInterval) == Double.infinity
				#endif
			}

			it("should negate as you'd hope") {
				expect((-DispatchTimeInterval.seconds(1)).timeInterval).to(beCloseTo(-1.0))
				expect((-DispatchTimeInterval.milliseconds(1)).timeInterval).to(beCloseTo(-0.001))
				expect((-DispatchTimeInterval.microseconds(1)).timeInterval).to(beCloseTo(-0.000001, within: 0.0000001))
				expect((-DispatchTimeInterval.nanoseconds(1)).timeInterval).to(beCloseTo(-0.000000001, within: 0.0000000001))
				#if swift(>=3.2)
					expect((-DispatchTimeInterval.never).timeInterval) == Double.infinity
				#endif
			}
		}
	}
}
