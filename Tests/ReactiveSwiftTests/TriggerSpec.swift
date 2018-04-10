//
//  TriggerSpec.swift
//  ReactiveSwift
//
//  Created by Marco Cancellieri on 10.04.18.
//  Copyright © 2018 GitHub. All rights reserved.
//

import Nimble
import Quick
import ReactiveSwift

class TriggerSpec: QuickSpec {
	override func spec() {
		describe("Trigger") {
			it("should send void if triggered") {
				let trigger = Trigger()
				var lastValue: ()?
				trigger.signal.observeValues { lastValue = $0 }
				expect(lastValue).to(beNil())
				trigger.fire()
				expect(lastValue).toNot(beNil())
			}
			it("should provide a BindingTarget") {
				let trigger = Trigger()
				var lastValue: ()?
				trigger.signal.observeValues { lastValue = $0 }
				expect(lastValue).to(beNil())
				trigger <~ SignalProducer(value: ())
				expect(lastValue).toNot(beNil())
			}
			it("should work as a BindingSource") {
				let trigger = Trigger()
				let lastValue = MutableProperty<()?>(nil)
				lastValue <~ trigger
				expect(lastValue.value).to(beNil())
				trigger.fire()
				expect(lastValue.value).toNot(beNil())
			}
			it("should capture an external Property") {
				let propertyToCapture = MutableProperty<()>(())
				let trigger = Trigger(capturing: propertyToCapture)
				
				let lastValue = MutableProperty<()?>(nil)
				lastValue <~ trigger
				
				expect(lastValue.value).to(beNil())
				propertyToCapture.value = ()
				expect(lastValue.value).toNot(beNil())
				lastValue.value = nil
				expect(lastValue.value).to(beNil())
				trigger.fire()
				expect(lastValue.value).toNot(beNil())
			}
		}
	}
}
