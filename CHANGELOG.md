# master
*Please add new entries at the top.*

1. New `Action` initializer that forwards inputs to an inner `Action` with the input transform applied. (#473, kudos to @andersio)

   The created `Action` shares the states of the wrapped `Action`, including the availability and execution status.

# 2.0.0-rc.2
1. Fixed a deadlock upon disposal when combining operators, i.e. `zip` and `combineLatest`, are used. (#471, kudos to @stevebrambilla for catching the bug)

# 2.0.0-rc.1
1. If the input observer of a `Signal` deinitializes while the `Signal` has not yet terminated, an `interrupted` event would now be automatically sent. (#463, kudos to @andersio)

1. `ValidationResult` and `ValidatorOutput` have been renamed to `ValidatingProperty.Result` and `ValidatingProperty.Decision`, respectively. (#443)

1. Mitigated a race condition related to ARC in the `Signal` internal. (#456, kudos to @andersio)

1. Added new convenience initialisers to `Action` that make creating actions with state input properties easier. When creating an `Action` that is conditionally enabled based on an optional property, use the renamed `Action.init(unwrapping:execute:)` initialisers. (#455, kudos to @sharplet)

# 2.0.0-alpha.3
1. `combinePrevious` for `Signal` and `SignalProducer` no longer requires an initial value. The first tuple would be emitted as soon as the second value is received by the operator if no initial value is given. (#445, kudos to @andersio)

1. Fixed an impedance mismatch in the `Signal` internals that caused heap corruptions. (#449, kudos to @gparker42)

1. In Swift 3.2 or later, you may create `BindingTarget` for a key path of a specific object. (#440, kudos to @andersio)

# 2.0.0-alpha.2
1. In Swift 3.2 or later, you can use `map()` with the new Smart Key Paths. (#435, kudos to @sharplet)

1. When composing `Signal` and `SignalProducer` of inhabitable types, e.g. `Never` or `NoError`, ReactiveSwift now warns about operators that are illogical to use, and traps at runtime when such operators attempt to instantiate an instance. (#429, kudos to @andersio)

1. N-ary `SignalProducer` operators are now generic and accept any type that can be expressed as `SignalProducer`. (#410, kudos to @andersio)
   Types may conform to `SignalProducerConvertible` to be an eligible operand.

1. The performance of `SignalProducer` has been improved significantly. (#140, kudos to @andersio)

   All lifted `SignalProducer` operators no longer yield an extra `Signal`. As a result, the calling overhead of event delivery is generally reduced proportionally to the level of chaining of lifted operators.
   
1. `interrupted` now respects `observe(on:)`. (#140)

   When a produced `Signal` is interrupted, if `observe(on:)` is the last applied operator, `interrupted` would now be delivered on the `Scheduler` passed to `observe(on:)` just like other events.

1. Feedbacks from `isExecuting` to the state of the same `Action`, including all `enabledIf` convenience initializers, no longer deadlocks. (#400, kudos to @andersio)

1. `MutableProperty` now enforces exclusivity of access. (#419, kudos to @andersio)

   In other words, nested modification in `MutableProperty.modify` is now prohibited. Generally speaking, it should have extremely limited impact as in most cases the `MutableProperty` would have been deadlocked already.

1. `promoteError` can now infer the new error type from the context. (#413, kudos to @andersio)

# 2.0.0-alpha.1
This is the first alpha release of ReactiveSwift 2.0. It requires Swift 3.1 (Xcode 8.3).

## Changes
### Modified `Signal` lifetime semantics (#355)
The `Signal` lifetime semantics is modified to improve interoperability with memory debugging tools. ReactiveSwift 2.0 adopted a new `Signal` internal which does not exploit deliberate retain cycles that consequentially confuse memory debugging tools.

A `Signal` is now automatically and silently disposed of, when:

1. the `Signal`  is not retained and has no active observer; or
1.  **(New)** both the `Signal`  and its input observer are not retained.

It is expected that memory debugging tools would no longer report irrelevant negative leaks that were once caused by the ReactiveSwift internals.

### `SignalProducer` resource management (#334)
`SignalProducer` now uses `Lifetime` for resource management. You may observe the `Lifetime` for the disposal of the produced `Signal`.

```swift
let producer = SignalProducer<Int, NoError> { observer, lifetime in
    if let disposable = numbers.observe(observer) {
        lifetime.observeEnded(disposable.dispose)
    }
}
```

Two `Disposable`-accepting methods `Lifetime.Type.+=` and `Lifetime.add` are provided to aid migration, and are subject to removal in a future release.

### Signal and SignalProducer 
1. All `Signal` and `SignalProducer` operators now belongs to the respective concrete types. (#304)

   Custom operators should extend the concrete types directly. `SignalProtocol` and `SignalProducerProtocol` should be used only for constraining associated types.

1. `combineLatest` and `zip` are optimised to have a constant overhead regardless of arity, mitigating the possibility of stack overflow. (#345) 

1. `flatMap(_:transform:)` is renamed to `flatMap(_:_:)`. (#339)

1. `promoteErrors(_:)`is renamed to `promoteError(_:)`. (#408)

1. `Event` is renamed to `Signal.Event`. (#376)

1. `Observer` is renamed to `Signal.Observer`. (#376)

### Action

1. `Action(input:_:)`, `Action(_:)`, `Action(enabledIf:_:)` and `Action(state:enabledIf:_:)` are renamed to `Action(state:execute:)`, `Action(execute:)`, `Action(enabledIf:execute:)` and `Action(state:enabledIf:execute:)` respectively. (#325)

### Properties
1. The memory overhead of property composition has been considerably reduced. (#340)

### Bindings
1. The `BindingSource` now requires only a producer representation of `self`. (#359)

1. The `<~` operator overloads are now provided by `BindingTargetProvider`. (#359)

### Disposables
1. `SimpleDisposable` and `ActionDisposable` has been folded into `AnyDisposable`. (#412)

1. `CompositeDisposable.DisposableHandle` is replaced by `Disposable?`. (#363)

1. The `+=` operator overloads for `CompositeDisposable` are now hosted inside the concrete types. (#412)

### Bag

1. Improved the performance of `Bag`. (#354)

1. `RemovalToken` is renamed to `Bag.Token`. (#354)

### Schedulers

1. `Scheduler` gains a class bound. (#333)

### Lifetime

1. `Lifetime.ended` now uses the inhabitable `Never` as its value type. (#392)

### Atomic

1. `Signal` and `Atomic` now use `os_unfair_lock` when it is available. (#342)

## Additions
1. `FlattenStrategy.race` is introduced. (#233, kudos to @inamiy)

   `race` flattens whichever inner signal that first sends an event, and ignores the rest.

1. `FlattenStrategy.concurrent` is introduced. (#298, kudos to @andersio)

   `concurrent` starts and flattens inner signals according to the specified concurrency limit. If an inner signal is received after the limit is reached, it would be queued and drained later as the in-flight inner signals terminate.

1. New operators: `reduce(into:)` and `scan(into:)`. (#365, kudos to @ikesyo)
 
   These variants pass to the closure an `inout` reference to the accumulator, which helps the performance when a large value type is used, e.g. collection.

1. `Property(initial:then:)` gains overloads that accept a producer or signal of the wrapped value type when the value type is an `Optional`. (#396)

## Deprecations and Removals
1. The requirement `BindingSource.observe(_:during:)` and the implementations have been removed.

1. All Swift 2 (ReactiveCocoa 4) obsolete symbols have been removed.

1. All deprecated methods and protocols in ReactiveSwift 1.1.x are no longer available.

## Acknowledgement

Thank you to all of @ReactiveCocoa/reactiveswift and all our contributors, but especially to @andersio, @calebd, @eimantas, @ikesyo, @inamiy, @Marcocanc, @mdiep, @NachoSoto, @sharplet and @tjnet. ReactiveSwift is only possible due to the many hours of work that these individuals have volunteered. ❤️

# 1.1.3
## Deprecation
1. `observe(_:during:)` is now deprecated. It would be removed in ReactiveSwift 2.0.
    Use `take(during:)` and the relevant observation API of `Signal`, `SignalProducer` and `Property` instead. (#374)
    
# 1.1.2
## Changes
1. Fixed a rare occurrence of `interrupted` events being emitted by a `Property`. (#362)

# 1.1.1
## Changes
1. The properties `Signal.negated`, `SignalProducer.negated` and `Property.negated` are deprecated. Use its operator form `negate()` instead.

# 1.1
## Additions

#### General
1. New boolean operators: `and`, `or` and `negated`; available on `Signal<Bool, E>`, `SignalProducer<Bool, E>` and `Property<Bool, E>` types. (#160, kudos to @cristianames92)
2. New operator `filterMap`. (#232, kudos to @RuiAAPeres)
3. New operator `lazyMap(on:_:)`. It coalesces `value` events when they are emitted at a rate faster than the rate the given scheduler can handle. The transform is applied on only the coalesced and the uncontended values. (#240, kudos to @liscio)
4. New protocol `BindingTargetProvider`, which replaces `BindingTargetProtocol`. (#254, kudos to @andersio)

#### SignalProducer
5. New initializer `SignalProducer(_:)`, which takes a `@escaping () -> Value` closure. It is similar to `SignalProducer(value:)`, but it lazily evaluates the value every time the producer is started. (#240, kudos to @liscio)

#### Lifetime
6. New method `Lifetime.observeEnded(self:)`. This is now the recommended way to explicitly observe the end of a `Lifetime`. Use `Lifetime.ended` only if composition is needed. (#229, kudos to @andersio)
7. New factory method `Lifetime.make()`, which returns a tuple of `Lifetime` and `Lifetime.Token`. (#236, kudos to @sharplet)

#### Properties
8. `ValidatingProperty`: A mutable property that validates mutations before committing them. (#182, kudos to @andersio).
9. A new interactive UI playground: `ReactiveSwift-UIExamples.playground`. It demonstrates how `ValidatingProperty` can be used in an interactive form UI. (#182)

## Changes
1. Flattening a signal of `Sequence` no longer requires an explicit `FlattenStrategy`. (#199, kudos to @dmcrodrigues)
2. `BindingSourceProtocol` has been renamed to `BindingSource`. (#254)
3. `SchedulerProtocol` and `DateSchedulerProtocol` has been renamed to `Scheduler` and `DateScheduler`, respectively. (#257)
4. `take(during:)` now handles ended `Lifetime` properly. (#229)

## Deprecations
1. `AtomicProtocol` has been deprecated. (#279)
2. `ActionProtocol` has been deprecated. (#284)
3. `ObserverProtocol` has been deprecated. (#262)
4. `BindingTargetProtocol` has been deprecated. (#254)

# 1.0.1
## Changes
1. Fixed a couple of infinite feedback loops in `Action`. (#221)
2. Fixed a race condition of `Signal` which might result in a deadlock when a signal is sent a terminal event as a result of an observer of it being released. (#267)

Kudos to @mdiep, @sharplet and @andersio who helped review the pull requests.

# 1.0

This is the first major release of ReactiveSwift, a multi-platform, pure-Swift functional reactive programming library spun off from [ReactiveCocoa](https://github.com/ReactiveCocoa/ReactiveCocoa). As Swift continues to expand beyond Apple’s platforms, we hope that ReactiveSwift will see broader adoption. To learn more, please refer to ReactiveCocoa’s [CHANGELOG](https://github.com/ReactiveCocoa/ReactiveCocoa/blob/master/CHANGELOG.md).

Major changes since ReactiveCocoa 4 include:
- **Updated for Swift 3**
  
  APIs have been updated and renamed to adhere to the Swift 3 [API Design Guidelines](https://swift.org/documentation/api-design-guidelines/).
- **Signal Lifetime Semantics**
  
  `Signal`s now live and continue to emit events only while either (a) they have observers or (b) they are retained. This clears up a number of unexpected cases and makes Signals much less dangerous.
- **Reactive Proxies**
  
  Types can now declare conformance to `ReactiveExtensionsProvider` to expose a `reactive` property that’s generic over `self`. This property hosts reactive extensions to the type, such as the ones provided on `NotificationCenter` and `URLSession`.
- **Property Composition**
  
  `Property`s can now be composed. They expose many of the familiar operators from `Signal` and `SignalProducer`, including `map`, `flatMap`, `combineLatest`, etc.
- **Binding Primitives**
  
  `BindingTargetProtocol` and `BindingSourceProtocol` have been introduced to allow binding of observable instances to targets. `BindingTarget` is a new concrete type that can be used to wrap a settable but non-observable property.
- **Lifetime**
  
  `Lifetime` is introduced to represent the lifetime of any arbitrary reference type. This can be used with the new `take(during:)` operator, but also forms part of the new binding APIs.
- **Race-free Action**
  
   A new `Action` initializer `Action(state:enabledIf:_:)` has been introduced. It allows the latest value of any arbitrary property to be supplied to the execution closure in addition to the input from `apply(_:)`, while having the availability being derived from the property.
  
   This eliminates a data race in ReactiveCocoa 4.x, when both the `enabledIf` predicate and the execution closure depend on an overlapping set of properties.

Extensive use of Swift’s `@available` declaration has been used to ease migration from ReactiveCocoa 4. Xcode should have fix-its for almost all changes from older APIs.

Thank you to all of @ReactiveCocoa/ReactiveSwift and all our contributors, but especially to @andersio, @liscio, @mdiep, @nachosoto, and @sharplet. ReactiveSwift is only possible due to the many hours of work that these individuals have volunteered. ❤️
