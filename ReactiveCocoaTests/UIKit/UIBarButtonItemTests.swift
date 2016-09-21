//
//  UIBarButtonItemTests.swift
//  Rex
//
//  Created by Andy Jacobs on 21/08/15.
//  Copyright (c) 2015 Neil Pankey. All rights reserved.
//

import ReactiveSwift
import ReactiveCocoa
import UIKit
import XCTest
import enum Result.NoError

class UIBarButtonItemTests: XCTestCase {

    weak var _barButtonItem: UIBarButtonItem?
    
    override func tearDown() {
        XCTAssert(_barButtonItem == nil, "Retain cycle detected in UIBarButtonItem properties")
        super.tearDown()
    }
    
    func testActionPropertyDoesntCreateRetainCycle() {
        let barButtonItem = UIBarButtonItem()
        _barButtonItem = barButtonItem
        
        let action = Action<(),(),NoError> {
            SignalProducer(value: ())
        }
        barButtonItem.rex_action <~ SignalProducer(value: CocoaAction(action, input: ()))
     }
    
    func testEnabledProperty() {
        let barButtonItem = UIBarButtonItem()
        barButtonItem.isEnabled = true
        
        let (pipeSignal, observer) = Signal<Bool, NoError>.pipe()
        barButtonItem.rex_enabled <~ SignalProducer(signal: pipeSignal)
        
        
        observer.sendNext(false)
        XCTAssertFalse(barButtonItem.isEnabled)
        observer.sendNext(true)
        XCTAssertTrue(barButtonItem.isEnabled)
    }
}
