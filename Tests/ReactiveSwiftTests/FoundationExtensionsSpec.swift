//
//  FoundationExtensionsSpec.swift
//  ReactiveSwift
//
//  Created by Neil Pankey on 5/22/15.
//  Copyright (c) 2015 GitHub. All rights reserved.
//

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
		describe("NSNotificationCenter.rac_notifications") {
			let center = NotificationCenter.default

			it("should send notifications on the producer") {
				let producer = center.rac_notifications(forName: .racFirst)

				var notif: Notification? = nil
				let disposable = producer.startWithValues { notif = $0 }

				center.post(name: .racAnother, object: nil)
				expect(notif).to(beNil())

				center.post(name: .racFirst, object: nil)
				expect(notif?.name) == .racFirst

				notif = nil
				disposable.dispose()

				center.post(name: .racFirst, object: nil)
				expect(notif).to(beNil())
			}

			it("should send Interrupted when the observed object is freed") {
				var observedObject: AnyObject? = NSObject()
				let producer = center.rac_notifications(forName: nil, object: observedObject)
				observedObject = nil

				var interrupted = false
				let disposable = producer.startWithInterrupted {
					interrupted = true
				}
				expect(interrupted) == true

				disposable.dispose()
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
			}

			it("should negate as you'd hope") {
				expect(-DispatchTimeInterval.seconds(1).timeInterval).to(beCloseTo(-1.0))
				expect(-DispatchTimeInterval.milliseconds(1).timeInterval).to(beCloseTo(-0.001))
				expect(-DispatchTimeInterval.microseconds(1).timeInterval).to(beCloseTo(-0.000001, within: 0.0000001))
				expect(-DispatchTimeInterval.nanoseconds(1).timeInterval).to(beCloseTo(-0.000000001, within: 0.0000000001))
			}
		}
	}
}
