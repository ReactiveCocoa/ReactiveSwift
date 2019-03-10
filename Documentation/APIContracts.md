# Design Guidelines

This document contains guidelines for projects that want to make use of
ReactiveSwift. The content here is heavily inspired by the [Rx Design
Guidelines](http://blogs.msdn.com/b/rxteam/archive/2010/10/28/rx-design-guidelines.aspx).

This document assumes basic familiarity
with the features of ReactiveSwift. The [Framework Overview][] is a better
resource for getting up to speed on the main types and concepts provided by ReactiveSwift.

**[The `Event` contract](#the-event-contract)**

 1. [`value`s provide values or indicate the occurrence of events](#values-provide-values-or-indicate-the-occurrence-of-events)
 1. [`failure`s behave like exceptions and propagate immediately](#failures-behave-like-exceptions-and-propagate-immediately)
 1. [`completion` indicates success](#completion-indicates-success)
 1. [`interruption`s cancel outstanding work and usually propagate immediately](#interruptions-cancel-outstanding-work-and-usually-propagate-immediately)
 1. [Events are serial](#events-are-serial)
 1. [Events are never delivered recursively, and values cannot be sent recursively](#events-are-never-delivered-recursively-and-values-cannot-be-sent-recursively)
 1. [Events are sent synchronously by default](#events-are-sent-synchronously-by-default)

**[The `Signal` contract](#the-signal-contract)**

 1. [Signals start work when instantiated](#signals-start-work-when-instantiated)
 1. [Observing a signal does not have side effects](#observing-a-signal-does-not-have-side-effects)
 1. [All observers of a signal see the same events in the same order](#all-observers-of-a-signal-see-the-same-events-in-the-same-order)
 1. [A signal is alive as long as it is publicly reachable or is being observed](#a-signal-is-alive-as-long-as-it-is-publicly-reachable-or-is-being-observed)
 1. [Terminating events dispose of signal resources](#terminating-events-dispose-of-signal-resources)

**[The `SignalProducer` contract](#the-signalproducer-contract)**

 1. [Signal producers start work on demand by creating signals](#signal-producers-start-work-on-demand-by-creating-signals)
 1. [Each produced signal may send different events at different times](#each-produced-signal-may-send-different-events-at-different-times)
 1. [Signal operators can be lifted to apply to signal producers](#signal-operators-can-be-lifted-to-apply-to-signal-producers)
 1. [Disposing of a produced signal will interrupt it](#disposing-of-a-produced-signal-will-interrupt-it)


**[The Property contract](#the-property-contract)**

 1. [A property must have its latest value sent synchronously accessible](#a-property-must-have-its-latest-value-sent-synchronously-accessible)
 1. [Events must be synchronously emitted after the mutation is visible](#events-must-be-synchronously-emitted-after-the-mutation-is-visible)
 1. [Reentrancy must be supported for reads](#reentrancy-must-be-supported-for-reads)
 1. [A composed property does not have a side effect on its sources, and does not own its lifetime](#a-composed-property-does-not-have-a-side-effect-on-its-sources-and-does-not-own-its-lifetime)

**[Best practices](#best-practices)**

 1. [Process only as many values as needed](#process-only-as-many-values-as-needed)
 1. [Observe events on a known scheduler](#observe-events-on-a-known-scheduler)
 1. [Switch schedulers in as few places as possible](#switch-schedulers-in-as-few-places-as-possible)
 1. [Capture side effects within signal producers](#capture-side-effects-within-signal-producers)
 1. [Share the side effects of a signal producer by sharing one produced signal](#share-the-side-effects-of-a-signal-producer-by-sharing-one-produced-signal)
 1. [Prefer managing lifetime with operators over explicit disposal](#prefer-managing-lifetime-with-operators-over-explicit-disposal)

**[Implementing new operators](#implementing-new-operators)**

 1. [Prefer writing operators that apply to both signals and producers](#prefer-writing-operators-that-apply-to-both-signals-and-producers)
 1. [Compose existing operators when possible](#compose-existing-operators-when-possible)
 1. [Forward failure and interruption events as soon as possible](#forward-failure-and-interruption-events-as-soon-as-possible)
 1. [Switch over `Event` values](#switch-over-event-values)
 1. [Avoid introducing concurrency](#avoid-introducing-concurrency)
 1. [Avoid blocking in operators](#avoid-blocking-in-operators)

## The `Event` contract

[Events][] are fundamental to ReactiveSwift. [Signals][] and [signal producers][] both send
events, and may be collectively called “event streams.”

Event streams must conform to the following grammar:

```
value* (interrupted | failed | completed)?
```

This states that an event stream consists of:

 1. Any number of `value` events
 1. Optionally followed by one terminating event, which is any of `interrupted`, `failed`, or `completed`

After a terminating event, no other events will be received.

#### `value`s provide values or indicate the occurrence of events

`value` events contain a payload known as the “value”. Only `value` events are
said to have a value. Since an event stream can contain any number of `value`s,
there are few restrictions on what those values can mean or be used for, except
that they must be of the same type.

As an example, the value might represent an element from a collection, or
a progress update about some long-running operation. The value of a `value` event
might even represent nothing at all—for example, it’s common to use a value type
of `()` to indicate that something happened, without being more specific about
what that something was.

Most of the event stream [operators][] act upon `value` events, as they represent the
“meaningful data” of a signal or producer.

#### `failure`s behave like exceptions and propagate immediately

`failed` events indicate that something went wrong, and contain a concrete error
that indicates what happened. Failures are fatal, and propagate as quickly as
possible to the consumer for handling.

Failures also behave like exceptions, in that they “skip” operators, terminating
them along the way. In other words, most [operators][] immediately stop doing
work when a failure is received, and then propagate the failure onward. This even applies to time-shifted operators, like [`delay`][delay]—which, despite its name, will forward any failures immediately.

Consequently, failures should only be used to represent “abnormal” termination. If it is important to let operators (or consumers) finish their work, a `value`
event describing the result might be more appropriate.

If an event stream can _never_ fail, it should be parameterized with the
special [`NoError`][NoError] type, which statically guarantees that a `failed`
event cannot be sent upon the stream.

#### `completion` indicates success

An event stream sends `completed` when the operation has completed successfully,
or to indicate that the stream has terminated normally.

Many operators manipulate the `completed` event to shorten or extend the
lifetime of an event stream.

For example, [`take`][take] will complete after the specified number of values have
been received, thereby terminating the stream early. On the other hand, most
operators that accept multiple signals or producers will wait until _all_ of
them have completed before forwarding a `completed` event, since a successful
outcome will usually depend on all the inputs.

#### `interruption`s cancel outstanding work and usually propagate immediately

An `interrupted` event is sent when an event stream should cancel processing.
Interruption is somewhere between [success](#completion-indicates-success)
and [failure](#failures-behave-like-exceptions-and-propagate-immediately)—the
operation was not successful, because it did not get to finish, but it didn’t
necessarily “fail” either.

Most [operators][] will propagate interruption immediately, but there are some
exceptions. For example, the [flattening operators][flatten] will ignore
`interrupted` events that occur on the _inner_ producers, since the cancellation
of an inner operation should not necessarily cancel the larger unit of work.

ReactiveSwift will automatically send an `interrupted` event upon [disposal][Disposables], but it can
also be sent manually if necessary. Additionally, [custom
operators](#implementing-new-operators) must make sure to forward interruption
events to the observer.

#### Events are serial

ReactiveSwift guarantees that all events upon a stream will arrive serially. In other
words, it’s impossible for the observer of a signal or producer to receive
multiple `Event`s concurrently, even if the events are sent on multiple threads
simultaneously.

This simplifies [operator][Operators] implementations and [observers][].

#### Events are never delivered recursively, and values cannot be sent recursively.

Just like [the guarantee of events not being delivered
concurrently](#events-are-serial), it is also guaranteed that events would not be
delivered recursively. As a consequence, [operators][] and [observers][] _do not_ need to
be reentrant.

If a `value` event is sent upon a signal from a thread that is _already processing_
a previous event from that signal, it would result in a deadlock. This is because
recursive signals are usually programmer error, and the determinacy of
a deadlock is preferable to nondeterministic race conditions.

Note that a terminal event is permitted to be sent recursively.

When a recursive signal is explicitly desired, the recursive event should be
time-shifted, with an operator like [`delay`][delay], to ensure that it isn’t sent from
an already-running event handler.

#### Events are sent synchronously by default

ReactiveSwift does not implicitly introduce concurrency or asynchrony. [Operators][] that
accept a [scheduler][Schedulers] may, but they must be explicitly invoked by the consumer of
the framework.

A “vanilla” signal or producer will send all of its events synchronously by
default, meaning that the [observer][Observers] will be synchronously invoked for each event
as it is sent, and that the underlying work will not resume until the event
handler finishes.

This is similar to how `NSNotificationCenter` or `UIControl` events are
distributed.

## The `Signal` contract

A [signal][Signals] is a stream of values that obeys [the `Event` contract](#the-event-contract).

`Signal` is a reference type, because each signal has identity — in other words, each
signal has its own lifetime, and may eventually terminate. Once terminated,
a signal cannot be restarted.

#### Signals start work when instantiated

[`Signal.init`][Signal.init] immediately executes the generator closure that is passed to it.
This means that side effects may occur even before the initializer returns.

It is also possible to send [events][] before the initializer returns. However,
since it is impossible for any [observers][] to be attached at this point, any
events sent this way cannot be received.

#### Observing a signal does not have side effects

The work associated with a `Signal` does not start or stop when [observers][] are
added or removed, so the [`observe`][observe] method (or the cancellation thereof) never
has side effects.

A signal’s side effects can only be stopped through [a terminating event](#signals-are-retained-until-a-terminating-event-occurs), or by a silent disposal at the point that [the signal is neither publicly reachable nor being observed](#a-signal-is-alive-as-long-as-it-is-publicly-reachable-or-is-being-observed).

#### All observers of a signal see the same events in the same order

Because [observation does not have side
effects](#observing-a-signal-does-not-have-side-effects), a `Signal` never
customizes events for different [observers][]. When an event is sent upon a signal,
it will be [synchronously](#events-are-sent-synchronously-by-default)
distributed to all observers that are attached at that time, much like
how `NSNotificationCenter` sends notifications.

In other words, there are not different event “timelines” per observer. All
observers effectively see the same stream of events.

There is one exception to this rule: adding an observer to a signal _after_ it
has already terminated will result in exactly one
[`interrupted`](#interruption-cancels-outstanding-work-and-usually-propagates-immediately)
event sent to that specific observer.

#### A signal is alive as long as it is publicly reachable or is being observed

A `Signal` must be publicly retained for attaching new observers, but not
necessarily for keeping the stream of events alive. Moreover, a `Signal` retains
itself as long as there is still an active observer.

In other words, if a `Signal` is neither publicly retained nor being observed,
it would dispose of the signal resources silently.

Note that the input observer of a signal does not retain the signal itself.

Long-running side effects are recommended to be modeled as an observer to the
signal.

#### Terminating events dispose of signal resources

When a terminating [event][Events] is sent along a `Signal`, all [observers][] will be
released, and any resources being used to generate events should be disposed of.

The easiest way to ensure proper resource cleanup is to return a [disposable][Disposables]
from the generator closure, which will be disposed of when termination occurs.
The disposable should be responsible for releasing memory, closing file handles,
canceling network requests, or anything else that may have been associated with
the work being performed.

## The `SignalProducer` contract

A [signal producer][Signal Producers] is like a “recipe” for creating
[signals][]. Signal producers do not do anything by themselves—[work begins only
when a signal is produced](#signal-producers-start-work-on-demand-by-creating-signals).

Since a signal producer is just a declaration of _how_ to create signals, it is
a value type, and has no memory management to speak of.

#### Signal producers start work on demand by creating signals

The [`start`][start] and [`startWithSignal`][startWithSignal] methods each
produce a `Signal` (implicitly and explicitly, respectively). After
instantiating the signal, the closure that was passed to
[`SignalProducer.init`][SignalProducer.init] will be executed, to start the flow
of [events][] after any observers have been attached.

Although the producer itself is not _really_ responsible for the execution of
work, it’s common to speak of “starting” and “canceling” a producer. These terms
refer to producing a `Signal` that will start work, and [disposing of that
signal](#disposing-of-a-produced-signal-will-interrupt-it) to stop work.

A producer can be started any number of times (including zero), and the work
associated with it will execute exactly that many times as well.

#### Each produced signal may send different events at different times

Because signal producers [start work on
demand](#signal-producers-start-work-on-demand-by-creating-signals), there may
be different [observers][] associated with each execution, and those observers
may see completely different [event][Events] timelines.

In other words, events are generated from scratch for each time the producer is
started, and can be completely different (or in a completely different order)
from other times the producer is started.

Nonetheless, each execution of a signal producer will follow [the `Event`
contract](#the-event-contract).

#### Signal operators can be lifted to apply to signal producers

Due to the relationship between signals and signal producers, it is possible to
automatically promote any [operators][] over one or more `Signal`s to apply to
the same number of `SignalProducer`s instead, using the [`lift`][lift] method.

`lift` will apply the behavior of the specified operator to each `Signal` that
is [created when the signal producer is started](#signal-producers-start-work-on-demand-by-creating-signals).

#### Disposing of a produced signal will interrupt it

When a producer is started using the [`start`][start] or
[`startWithSignal`][startWithSignal] methods, a [`Disposable`][Disposables] is
automatically created and passed back.

Disposing of this object will
[interrupt](#interruption-cancels-outstanding-work-and-usually-propagates-immediately)
the produced `Signal`, thereby sending an
`interrupted` [event][Events] to all [observers][]. Anything associated with the `Lifetime` of the produced `Signal` is disposed of afterwards.

Note that disposing of one produced `Signal` will not affect other signals created
by the same `SignalProducer`.

## The Property contract

A property is essentially a `Signal` which guarantees it has an initial value, and its latest value is always available for being read out.

All read-only property types should conform to `PropertyProtocol`, while the mutable counterparts should conform to `MutablePropertyProtocol`. ReactiveSwift includes two primitives that implement the contract: `Property` and `MutableProperty`.

#### A property must have its latest value sent synchronously accessible.

A property must have its latest value cached or stored at any point of time. It must be synchronously accessible through `PropertyProtocol.value`.

The `SignalProducer` of a property must replay the latest value before forwarding subsequent changes, and it may ensure that no race condition exists between the replaying and the setup of the forwarding.

#### Events must be synchronously emitted after the mutation is visible.

A mutable property must emit its values and the `completed` event synchronously.

The observers of a property should always observe the same value from the signal and the producer as  `PropertyProtocol.value`. This implies that all observations are a `didSet` observer.

#### Reentrancy must be supported for reads.

All properties must guarantee that observers reading `PropertyProtocol.value` would not deadlock.

In other words, if a mutable property type implements its own, or inherits a synchronization mechanism from its container, the synchronization generally should be reentrant due to the requirements of synchrony.

#### A composed property does not have a side effect on its sources, and does not own its lifetime.

A composed property presents a transformed view of its sources. It should not have a side effect on them, as [observing a signal does not have side effects](#observing-a-signal-does-not-have-side-effects) either. This implies a composed property should never retain its sources, or otherwise the `completed` event emitted upon deinitialization would be influenced.

Moreover, it does not own its lifetime, and its deinitialization should not affect its signal and its producer. The signal and the producer should respect the lifetime of the ultimate sources in a property composition graph.

## Best practices

The following recommendations are intended to help keep ReactiveSwift-based code
predictable, understandable, and performant.

They are, however, only guidelines. Use best judgement when determining whether
to apply the recommendations here to a given piece of code.

#### Process only as many values as needed

Keeping an event stream alive longer than necessary can waste CPU and memory, as
unnecessary work is performed for results that will never be used.

If only a certain number of values or certain number of time is required from
a [signal][Signals] or [producer][Signal Producers], operators like
[`take`][take] or [`takeUntil`][takeUntil] can be used to
automatically complete the stream once a certain condition is fulfilled.

The benefit is exponential, too, as this will terminate dependent operators
sooner, potentially saving a significant amount of work.

#### Observe events on a known scheduler

When receiving a [signal][Signals] or [producer][Signal Producers] from unknown
code, it can be difficult to know which thread [events][] will arrive upon. Although
events are [guaranteed to be serial](#events-are-serial), sometimes stronger
guarantees are needed, like when performing UI updates (which must occur on the
main thread).

Whenever such a guarantee is important, the [`observeOn`][observeOn]
[operator][Operators] should be used to force events to be received upon
a specific [scheduler][Schedulers].

#### Switch schedulers in as few places as possible

Notwithstanding the [above](#observe-events-on-a-known-scheduler), [events][]
should only be delivered to a specific [scheduler][Schedulers] when absolutely
necessary. Switching schedulers can introduce unnecessary delays and cause an
increase in CPU load.

Generally, [`observeOn`][observeOn] should only be used right before observing
the [signal][Signals], starting the [producer][Signal Producers], or binding to
a [property][Properties]. This ensures that events arrive on the expected
scheduler, without introducing multiple thread hops before their arrival.

#### Capture side effects within signal producers

Because [signal producers start work on
demand](#signal-producers-start-work-on-demand-by-creating-signals), any
functions or methods that return a [signal producer][Signal Producers] should
make sure that side effects are captured _within_ the producer itself, instead
of being part of the function or method call.

For example, a function like this:

```swift
func search(text: String) -> SignalProducer<Result, NetworkError>
```

… should _not_ immediately start a search.

Instead, the returned producer should execute the search once for every time
that it is started. This also means that if the producer is never started,
a search will never have to be performed either.

#### Share the side effects of a signal producer by sharing one produced signal

If multiple [observers][] are interested in the results of a [signal
producer][Signal Producers], calling [`start`][start] once for each observer
means that the work associated with the producer will [execute that many
times](#signal-producers-start-work-on-demand-by-creating-signals) and [may not
generate the same results](#each-produced-signal-may-send-different-events-at-different-times).

If:

 1. the observers need to receive the exact same results
 1. the observers know about each other, or
 1. the code starting the producer knows about each observer

… it may be more appropriate to start the producer _just once_, and share the
results of that one [signal][Signals] to all observers, by attaching them within
the closure passed to the [`startWithSignal`][startWithSignal] method.

#### Prefer managing lifetime with operators over explicit disposal

Although the [disposable][Disposables] returned from [`start`][start] makes
canceling a [signal producer][Signal Producers] really easy, explicit use of
disposables can quickly lead to a rat's nest of resource management and cleanup
code.

There are almost always higher-level [operators][] that can be used instead of manual
disposal:

 * [`take`][take] can be used to automatically terminate a stream once a certain
   number of values have been received.
 * [`takeUntil`][takeUntil] can be used to automatically terminate
   a [signal][Signals] or producer when an event occurs (for example, when
   a “Cancel” button is pressed in the UI).
 * [Properties][] and the `<~` operator can be used to “bind” the result of
   a signal or producer, until termination or until the property is deallocated.
   This can replace a manual observation that sets a value somewhere.

## Implementing new operators

ReactiveSwift provides a long list of built-in [operators][] that should cover most use
cases; however, ReactiveSwift is not a closed system. It's entirely valid to implement
additional operators for specialized uses, or for consideration in ReactiveSwift
itself.

Implementing a new operator requires a careful attention to detail and a focus
on simplicity, to avoid introducing bugs into the calling code.

These guidelines cover some of the common pitfalls and help preserve the
expected API contracts. It may also help to look at the implementations of
existing [`Signal`][Signals] and [`SignalProducer`][Signal Producers] operators for reference points.

#### Prefer writing operators that apply to both signals and producers

Since any [signal operator can apply to signal
producers](#signal-operators-can-be-lifted-to-apply-to-signal-producers),
writing custom operators in terms of [`Signal`][Signals] means that
[`SignalProducer`][Signal Producers] will get it “for free.”

Even if the caller only needs to apply the new operator to signal producers at
first, this generality can save time and effort in the future.

Of course, some capabilities _require_ producers (for example, any retrying or
repeating), so it may not always be possible to write a signal-based version
instead.

#### Compose existing operators when possible

Considerable thought has been put into the operators provided by ReactiveSwift, and they
have been validated through automated tests and through their real world use in
other projects. An operator that has been written from scratch may not be as
robust, or might not handle a special case that the built-in operators are aware
of.

To minimize duplication and possible bugs, use the provided operators as much as
possible in a custom operator implementation. Generally, there should be very
little code written from scratch.

#### Forward failure and interruption events as soon as possible

Unless an operator is specifically built to handle
[failures](#failures-behave-like-exceptions-and-propagate-immediately) and
[interruptions](#interruption-cancels-outstanding-work-and-usually-propagates-immedaitely)
in a custom way, it should propagate those events to the observer as soon as
possible, to ensure that their semantics are honored.

#### Switch over `Event` values

Create your own [observer][Observers] to process raw [`Event`][Events] values, and use
a `switch` statement to determine the event type.

For example:

```swift
producer.start { event in
    switch event {
    case let .value(value):
        print("Value event: \(value)")

    case let .failed(error):
        print("Failed event: \(error)")

    case .completed:
        print("Completed event")

    case .interrupted:
        print("Interrupted event")
    }
}
```

Since the compiler will generate a warning if the `switch` is missing any case,
this prevents mistakes in a custom operator’s event handling.

#### Avoid introducing concurrency

Concurrency is an extremely common source of bugs in programming. To minimize
the potential for deadlocks and race conditions, operators should not
concurrently perform their work.

Callers always have the ability to [observe events on a specific
scheduler](#observe-events-on-a-known-scheduler), and ReactiveSwift offers built-in ways
to parallelize work, so custom operators don’t need to be concerned with it.

#### Avoid blocking in operators

Signal or producer operators should return a new signal or producer
(respectively) as quickly as possible. Any work that the operator needs to
perform should be part of the event handling logic, _not_ part of the operator
invocation itself.

This guideline can be safely ignored when the purpose of an operator is to
synchronously retrieve one or more values from a stream, like `single()` or
`wait()`.

[CompositeDisposable]: ../Sources/Disposable.swift
[Disposables]: FrameworkOverview.md#disposables
[Events]: FrameworkOverview.md#events
[Framework Overview]: FrameworkOverview.md
[NoError]: ../Sources/Errors.swift
[Observers]: FrameworkOverview.md#observers
[Operators]: BasicOperators.md
[Properties]: FrameworkOverview.md#properties
[Schedulers]: FrameworkOverview.md#schedulers
[Signal Producers]: FrameworkOverview.md#signal-producers
[Signal.init]: ../Sources/Signal.swift
[Signal.pipe]: ../Sources/Signal.swift
[SignalProducer.init]: ../Sources/SignalProducer.swift
[Signals]: FrameworkOverview.md#signals
[delay]: ../Sources/Signal.swift
[flatten]: BasicOperators.md#flattening-producers
[lift]: ../Sources/SignalProducer.swift
[observe]: ../Sources/Signal.swift
[observeOn]: ../Sources/Signal.swift
[start]: ../Sources/SignalProducer.swift
[startWithSignal]: ../Sources/SignalProducer.swift
[take]: ../Sources/Signal.swift
[takeUntil]: ../Sources/Signal.swift
