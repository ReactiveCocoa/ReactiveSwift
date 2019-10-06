//
//  ObservablePropertyWrapperSpec.swift
//  
//
//  Created by Petr on 05/10/2019.
//

import Foundation
import Dispatch
import Nimble
import Quick
@testable import ReactiveSwift

class ObservablePropertyWrapperSpec: QuickSpec {
    #if swift(>=5.1)

    private class TestCounter {
        @Observable private(set) var value: Int = 0

        func increment() {
            value += 1
        }
    }

    override func spec() {
        describe("ObservablePropertyWrapper") {
            it("value and underlyin's property value should be the same") {
                let counter = TestCounter()

                expect(counter.value) == 0
                expect(counter.$value.property.value) == 0
                counter.increment()
                expect(counter.value) == 1
                expect(counter.$value.property.value) == 1
            }
            it("signal should match underlying peoperty's signal") {
                let counter = TestCounter()
                expect(counter.$value.signal) === counter.$value.property.signal
            }
        }
    }
    #endif
}
