//
//  ObservablePropertyWrapper.swift
//  
//
//  Created by Petr Pavlik on 05/10/2019.
//

#if swift(>=5.1)

/// Property wrapper that allows observation of  changes, backed by `Property`.
@propertyWrapper
public struct Observable<Value> {

    private let mutableProperty: MutableProperty<Value>

    /// Provides access to underlying `Property` object.
    public let property: Property<Value>

    /// A signal that will send the property's changes over time,
    /// then complete when the property has deinitialized.
    public var signal: Signal<Value, Never> { property.signal }

    /// A producer for Signals that will send the property's current value,
    /// followed by all changes over time, then complete when the property has
    /// deinitialized.
    public var producer: SignalProducer<Value, Never> { property.producer }

    public var wrappedValue: Value {
        set { mutableProperty.value = newValue }
        get { mutableProperty.value }
    }

    public var projectedValue: Self {
      get { self }
      set { self = newValue }
    }

    public init(wrappedValue: Value) {
        self.mutableProperty = MutableProperty<Value>(wrappedValue)
        self.property =  Property<Value>(mutableProperty)
    }
}

#endif
