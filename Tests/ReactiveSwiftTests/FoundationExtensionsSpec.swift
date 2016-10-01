//
//  FoundationExtensionsSpec.swift
//  ReactiveSwift
//
//  Created by Neil Pankey on 5/22/15.
//  Copyright (c) 2015 GitHub. All rights reserved.
//

import Foundation

import Result
import Nimble
import Quick
import ReactiveSwift

extension Notification.Name {
	static let racFirst = Notification.Name(rawValue: "rac_notifications_test")
	static let racAnother = Notification.Name(rawValue: "rac_notifications_another")
}

class FoundationExtensionsSpec: QuickSpec {
	override func spec() {
		describe("Reactivity<NotificationCenter>.notifications") {
			let center = NotificationCenter.default

			it("should send notifications on the producer") {
				let producer = center.rac.notifications(forName: .racFirst)

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
				let producer = center.rac.notifications(forName: nil, object: observedObject)
				observedObject = nil

				var interrupted = false
				let disposable = producer.startWithInterrupted {
					interrupted = true
				}
				expect(interrupted) == true

				disposable.dispose()
			}

		}
	}
}
