//
//  CocoaAction.swift
//  Rex
//
//  Created by Neil Pankey on 6/19/15.
//  Copyright (c) 2015 Neil Pankey. All rights reserved.
//

import ReactiveSwift
import ReactiveCocoa
import enum Result.NoError

extension CocoaAction {
    /// Creates an always disabled action that can be used as a default for
    /// things like `rac_pressed`.
    public static var rex_disabled: CocoaAction {
        return CocoaAction(Action<Any?, (), NoError>.rex_disabled, input: nil)
    }

    /// Creates a producer for the `enabled` state of a CocoaAction.
    public var rex_enabledProducer: SignalProducer<Bool, NoError> {
        return rex_producer(forKeyPath: #keyPath(CocoaAction.isEnabled))
    }

    /// Creates a producer for the `executing` state of a CocoaAction.
    public var rex_executingProducer: SignalProducer<Bool, NoError> {
        return rex_producer(forKeyPath: #keyPath(CocoaAction.isExecuting))
    }
}
