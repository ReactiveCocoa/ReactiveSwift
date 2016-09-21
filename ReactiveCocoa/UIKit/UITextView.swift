//
//  UITextView.swift
//  Rex
//
//  Created by Rui Peres on 05/04/2016.
//  Copyright © 2016 Neil Pankey. All rights reserved.
//

import ReactiveSwift
import UIKit
import enum Result.NoError

extension UITextView {
    
    /// Sends the textView's string value whenever it changes.
    public var rex_text: SignalProducer<String, NoError> {
        return NotificationCenter.default
            .rac_notifications(forName: .UITextViewTextDidChange, object: self)
            .filterMap  { ($0.object as? UITextView)?.text }
    }
}
