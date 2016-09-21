//
//  UIView.swift
//  Rex
//
//  Created by Andy Jacobs on 21/10/15.
//  Copyright © 2015 Neil Pankey. All rights reserved.
//

import ReactiveSwift
import UIKit

extension UIView {
    /// Wraps a view's `alpha` value in a bindable property.
    public var rex_alpha: MutableProperty<CGFloat> {
        return associatedProperty(self, key: &alphaKey, initial: { $0.alpha }, setter: { $0.alpha = $1 })
    }
    
    /// Wraps a view's `hidden` state in a bindable property.
    public var rex_hidden: MutableProperty<Bool> {
        return associatedProperty(self, key: &hiddenKey, initial: { $0.isHidden }, setter: { $0.isHidden = $1 })
    }
    

    /// Wraps a view's `userInteractionEnabled` state in a bindable property.
    public var rex_userInteractionEnabled: MutableProperty<Bool> {
        return associatedProperty(self, key: &userInteractionEnabledKey, initial: { $0.isUserInteractionEnabled }, setter: { $0.isUserInteractionEnabled = $1 })
    }
}

private var alphaKey: UInt8 = 0
private var hiddenKey: UInt8 = 0
private var userInteractionEnabledKey: UInt8 = 0
