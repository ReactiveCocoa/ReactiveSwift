//
//  UIControl+EnableSendActionsForControlEvents.swift
//  Rex
//
//  Created by David Rodrigues on 24/04/16.
//  Copyright © 2016 Neil Pankey. All rights reserved.
//

import UIKit

private let rex_swizzleToken: Void = {
    let originalSelector = #selector(UIControl.sendAction(_:to:for:))
    let swizzledSelector = #selector(UIControl.rex_sendAction(_:to:forEvent:))

    let originalMethod = class_getInstanceMethod(UIControl.self, originalSelector)
    let swizzledMethod = class_getInstanceMethod(UIControl.self, swizzledSelector)

    let didAddMethod = class_addMethod(UIControl.self,
                                       originalSelector,
                                       method_getImplementation(swizzledMethod),
                                       method_getTypeEncoding(swizzledMethod))

    if didAddMethod {
        class_replaceMethod(UIControl.self,
                            swizzledSelector,
                            method_getImplementation(originalMethod),
                            method_getTypeEncoding(originalMethod))
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    return ()
}()

/// Unfortunately, there's an apparent limitation in using `sendActionsForControlEvents`
/// on unit-tests for any control besides `UIButton` which is very unfortunate since we
/// want test our bindings for `UIDatePicker`, `UISwitch`, `UITextField` and others
/// in the future. To be able to test them, we're now using swizzling to manually invoke
/// the pair target+action.
extension UIControl {

    override open class func initialize() {
        if self !== UIControl.self {
            return
        }

        _ = rex_swizzleToken
    }

    // MARK: - Method Swizzling

    func rex_sendAction(_ action: Selector, to target: AnyObject?, forEvent event: UIEvent?) {
        _ = target?.perform(action, with: self)
    }
}
