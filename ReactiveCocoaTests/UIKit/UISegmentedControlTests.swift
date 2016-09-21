//
//  UISegmentedControlTests.swift
//  Rex
//
//  Created by Markus Chmelar on 07/06/16.
//  Copyright © 2016 Neil Pankey. All rights reserved.
//

import XCTest
import ReactiveSwift
import ReactiveCocoa
import Result

class UISegmentedControlTests: XCTestCase {
    
    func testSelectedSegmentIndexProperty() {
        let s = UISegmentedControl(items: ["0", "1", "2"])
        s.selectedSegmentIndex = UISegmentedControlNoSegment
        XCTAssertEqual(s.numberOfSegments, 3)
        
        let (pipeSignal, observer) = Signal<Int, NoError>.pipe()
        s.rex_selectedSegmentIndex <~ SignalProducer(signal: pipeSignal)
        
        XCTAssertEqual(s.selectedSegmentIndex, UISegmentedControlNoSegment)
        observer.sendNext(1)
        XCTAssertEqual(s.selectedSegmentIndex, 1)
        observer.sendNext(2)
        XCTAssertEqual(s.selectedSegmentIndex, 2)
    }
}
