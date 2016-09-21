//
//  UIBarItem.swift
//  Rex
//
//  Created by Bjarke Hesthaven Søndergaard on 24/07/15.
//  Copyright (c) 2015 Neil Pankey. All rights reserved.
//

import ReactiveSwift
import UIKit

extension UIBarItem {
    /// Wraps a UIBarItem's `enabled` state in a bindable property.
    public var rex_enabled: MutableProperty<Bool> {
        return associatedProperty(self, key: &enabledKey, initial: { $0.isEnabled }, setter: { $0.isEnabled = $1 })
    }
}

private var enabledKey: UInt8 = 0
