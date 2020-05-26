# The ReactiveSwift X initiative
ReactiveSwift has passed its 5th anniversary in March 2020. Since its very first ReactiveCocoa 3.0 alpha release in March 2015, ReactiveSwift has witnessed Swift as the rising star in macOS and iOS development and its constant evolution. It has withstood the tides of competing reactive programming frameworks. 

ReactiveSwift will remain as your opinionated option for Swift reactive programming, and a production-proven choice to support your applications.

The ReactiveSwift X (Ten) initiative aims at bringing in new capabilities, while maintaining the ReactiveSwift idiomaticity of fostering user intuition and keeping the API surface simple.

## Table of Contents

- [Backpressure and Reactive Pull support](#backpressure-and-reactive-pull-support)
- [Stream-of-one primitives](#stream-of-one-primitivies)
- [Tagless Final encoding, and the implementation strategy for streams-of-one primitives](#tagless-final-encoding-and-the-implementation-strategy-for-streams-of-one-primitives)
- [Property enhancements](#property-enhancements)
- [In-built Combine interoperability](#in-built-combine-interoperability)

## Backpressure and Reactive Pull support
Migrate `SignalProducer` to a _reactive pull model_ akin to Reactive Streams and Apple Combine, while preserving source compatibility and existing developer experience.

### Implementation plan
1. Overhaul the representation of observers in RAS internals, by splitting the event sink up into two sinks: value and termination.
As a side effect, it shall reduce runtime cost in enum (un)packing for value events. It shall also enable the large value pass-by-pointer optimisation to take place more often.
2. Formally established the concept of **producer subscriptions** in RAS internals, which should start with the cancellation API.
This shall also clean up some obscure signatures, e.g. `start` with a signature of `(_: (Disposable) -> Observer) -> Disposable`,  introduced since the ReactiveSwift 3.0 producer overhaul.
3. Implement the reactive pull model. Extend the subscription API to support demand requests.

## Stream-of-one primitives
We shall offer a more refined set of API for the common stream-of-one-event scenario in application development, covering both the calling for cold and hot primitives. The approach presented below should address concerns raised in previous discussions (#661, #668).

The main arguments _against_ the addition was unassurance of its value over `SignalProducer`, and the unclarity in what semantics ReactiveSwift should offer. It is believed that the API annotation benefit, the popularity of the target use cases, and the streamlined API surface (at static time) are all compelling factors to pursue the project. The initiative proposes to offer **both** hot and cold streams-of-one-event:

* Support a **cold** “single” producer  `ProducerOfOne<U, E>` (name inspired by `Swift.CollectionOfOne`).

  Refined interfaces include strategy-less `flatMap` and exclusion of most multi-value operators like `filter`, `skip` and `take`.

* Support a **hot** promise `Future<U, E>`.

  It should offer a similarly refined interface to `ProducerOfOne<U, E>`.
  
* Conversions between cold and hot streams-of-one-event.

* New `Signal` and `SignalProducer` operators to convert to these refined types.

  e.g. `SignalProducer.takeFirst()` that guarantees a `ProducerOfOne`.

## Tagless Final encoding, and the implementation strategy for streams-of-one primitives
Instead of wrapping `SignalProducer` and `Property` with new types, we may adopt the tagless final encoding proposed in #722 by @inamiy, but only over the value type. Given the new producer type `_Producer<TLF, E>`  and the new property type  `_Prop<TLF, E>`, the `TLF` type parameter shall encode not only the type of value the stream sends, but also a static constraint of _how many_ values to be produced.

The encoding enables us to express specialised operators by refining constraints on the tagless final generic parameter. This was impossible in the current setting, given `SignalProducer` defaulting to multi values, and negative constraints being a Swift non-goal.

For example, the new gained generic expressivity allows the `take()` family to only present for multi-value producers:
```swift
extension _Producer where Value == Never {
  // Offer none of the `take()` operator family.
}

extension _Producer where Value: OnceValueProtocol {
  // Offer none of the `take()` operator family.
}

extension _Producer where Value: MultiValueProtocol {
  func takeFirst() -> SignalProducer<Once<Value.Value, Error>
  func take(first count: Int) -> SignalProducer<Multi<Value.Value, Error>
}
```

Specialised spellings under this scheme can then be implemented as simple typealiases, e.g.:

* `SignalProducer`  as `P<Multi<Value>, E>`

*  `ProducerOfOnce`  as `P<Once<Value>, E>`

* hypothetically, `Completable<E>` as `P<Never, E>` (out of scope)

## Property enhancements
* MutableProperty to subclass Property: enabling type erasure given that no value type can satisfy the contract.

* MutableProperty WritableKeyPath lenses.

## In-built Combine interoperability
