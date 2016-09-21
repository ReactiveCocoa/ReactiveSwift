//
//  UIView.swift
//  Rex
//
//  Created by Neil Pankey on 6/19/15.
//  Copyright (c) 2015 Neil Pankey. All rights reserved.
//

import ReactiveSwift
import UIKit
import enum Result.NoError

extension UIControl {

#if os(iOS)
    /// Creates a producer for the sender whenever a specified control event is triggered.
    public func rex_controlEvents(_ events: UIControlEvents) -> SignalProducer<UIControl?, NoError> {
        return rac_signal(for: events)
            .toSignalProducer()
            .map { $0 as? UIControl }
            .flatMapError { _ in SignalProducer(value: nil) }
    }

    /// Creates a bindable property to wrap a control's value.
    /// 
    /// This property uses `UIControlEvents.ValueChanged` and `UIControlEvents.EditingChanged` 
    /// events to detect changes and keep the value up-to-date.
    //
    class func rex_value<Host: UIControl, T>(_ host: Host, getter: @escaping (Host) -> T, setter: @escaping (Host, T) -> ()) -> MutableProperty<T> {
        return associatedProperty(host, key: &valueChangedKey, initial: getter, setter: setter) { property in
            property <~
                host.rex_controlEvents([.valueChanged, .editingChanged])
                    .filterMap { $0 as? Host }
                    .filterMap(getter)
        }
    }
#endif

    /// Wraps a control's `enabled` state in a bindable property.
    public var rex_enabled: MutableProperty<Bool> {
        return associatedProperty(self, key: &enabledKey, initial: { $0.isEnabled }, setter: { $0.isEnabled = $1 })
    }
    
    /// Wraps a control's `selected` state in a bindable property.
    public var rex_selected: MutableProperty<Bool> {
        return associatedProperty(self, key: &selectedKey, initial: { $0.isSelected }, setter: { $0.isSelected = $1 })
    }
    
    /// Wraps a control's `highlighted` state in a bindable property.
    public var rex_highlighted: MutableProperty<Bool> {
        return associatedProperty(self, key: &highlightedKey, initial: { $0.isHighlighted }, setter: { $0.isHighlighted = $1 })
    }
}

private var enabledKey: UInt8 = 0
private var selectedKey: UInt8 = 0
private var highlightedKey: UInt8 = 0
private var valueChangedKey: UInt8 = 0
