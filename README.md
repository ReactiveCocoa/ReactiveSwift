<p align="center">
	<a href="https://github.com/ReactiveCocoa/ReactiveSwift/"><img src="Logo/PNG/logo-Swift.png" alt="ReactiveSwift" /></a><br /><br />
	Streams of values over time. Tailored for Swift.<br /><br />
	<a href="http://reactivecocoa.io/reactiveswift/docs/latest/"><img src="Logo/PNG/Docs.png" alt="Latest ReactiveSwift Documentation" width="143" height="40" /></a> <a href="http://reactivecocoa.io/slack/"><img src="Logo/PNG/JoinSlack.png" alt="Join the ReactiveSwift Slack community." width="143" height="40" /></a>
</p>
<br />

[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](#carthage) [![CocoaPods compatible](https://img.shields.io/cocoapods/v/ReactiveSwift.svg)](#cocoapods) [![SwiftPM compatible](https://img.shields.io/badge/SwiftPM-compatible-orange.svg)](#swift-package-manager) [![GitHub release](https://img.shields.io/github/release/ReactiveCocoa/ReactiveSwift.svg)](https://github.com/ReactiveCocoa/ReactiveSwift/releases) ![Swift 3.0.x](https://img.shields.io/badge/Swift-3.0.x-orange.svg) ![platforms](https://img.shields.io/badge/platform-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20Linux-lightgrey.svg)

☕️ [Looking for Cocoa extensions?][ReactiveCocoa]
🎉 [Getting Started](#getting-started)
⚠️ [Still using Swift 2.x?][]


🚄 [Release Roadmap](#release-roadmap)
## What is ReactiveSwift?
__ReactiveSwift__ offers composable, declarative and flexible primitives that are built around the grand concept of ___streams of values over time___.

These primitives can be used to uniformly represent common Cocoa and generic programming patterns that are fundamentally an act of observation, e.g. delegate pattern, callback closures, notifications, control actions, responder chain events, [futures/promises](https://en.wikipedia.org/wiki/Futures_and_promises) and [key-value observing](https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/KeyValueObserving/KeyValueObserving.html) (KVO).

Because all of these different mechanisms can be represented in the _same_ way,
it’s easy to declaratively compose them together, with less spaghetti
code and state to bridge the gap.

### Core Reactive Primitives
#### `Signal`: a unidirectional stream of events.
The owner of a `Signal` has unilateral control of the event stream. Observers may register their interests in the future events at any time, but the observation would have no side effect on the stream or its owner.

It is like a live TV feed — you can observe and react to the content, but you cannot have a side effect on the live feed or the TV station.

```swift
let channel: Signal<Program, NoError> = tvStation.channelOne
channel.observeValues { program in ... }
```

#### `Event`: the basic transfer unit of an event stream.
A `Signal` may have any arbitrary number of events carrying a value, following by an eventual terminal event of a specific reason.

It is like a frame in a one-time live feed — seas of data frames carry the visual and audio data, but the feed would eventually be terminated with a special frame to indicate "end of stream".

#### `SignalProducer`: deferred work that creates a stream of values.
`SignalProducer` defers work — of which the output is represented as a stream of values — until it is started. For every invocation to start the `SignalProducer`, a new `Signal` is created and the deferred work is subsequently invoked.

It is like a on-demand streaming service — even though the episode is streamed like a live TV feed, you can choose what you watch, when to start watching and when to interrupt it.


```swift
let frames: SignalProducer<VideoFrame, ConnectionError> = vidStreamer.streamAsset(id: tvShowId)
let interrupter = frames.start { frame in ... }
interrupter.dispose()
```

#### `Lifetime`: limits the scope of an observation
When observing a `Signal` or `SignalProducer`, it doesn't make sense to continue emitting values if there's no longer anyone observing them.
Consider the video stream: once you stop watching the video, the stream can be automatically closed by providing a `Lifetime`:

```swift
class VideoPlayer {
  private let (lifetime, token) = Lifetime.make()

  func play() {
    let frames: SignalProducer<VideoFrame, ConnectionError> = ...
    frames.take(during: lifetime).start { frame in ... }
  }
}
```

#### `Property`: an observable box that always holds a value.
`Property` is a variable that can be observed for its changes. In other words, it is a stream of values with a stronger guarantee than `Signal` — the latest value is always available, and the stream would never fail.

It is like the continuously updated current time offset of a video playback — the playback is always at a certain time offset at any time, and it would be updated by the playback logic as the playback continues.

```swift
let currentTime: Property<TimeInterval> = video.currentTime
print("Current time offset: \(currentTime.value)")
currentTime.signal.observeValues { timeBar.timeLabel.text = "\($0)" }
```

#### `Action`: a serialized worker with a preset action.
When being invoked with an input, `Action` apply the input and the latest state to the preset action, and pushes the output to any interested parties.

It is like an automatic vending machine — after choosing an option with coins inserted, the machine would process the order and eventually output your wanted snack. Notice that the entire process is mutually exclusive — you cannot have the machine to serve two customers concurrently.

```swift
// Purchase from the vending machine with a specific option.
vendingMachine.purchase
    .apply(snackId)
    .startWithResult { result
        switch result {
        case let .success(snack):
            print("Snack: \(snack)")

        case let .failure(error):
            // Out of stock? Insufficient fund?
            print("Transaction aborted: \(error)")
        }
    }

// The vending machine.
class VendingMachine {
    let purchase: Action<Int, Snack, VendingMachineError>
    let coins: MutableProperty<Int>

    // The vending machine is connected with a sales recorder.
    init(_ salesRecorder: SalesRecorder) {
        coins = MutableProperty(0)
        purchase = Action(state: coins, enabledIf: { $0 > 0 }) { coins, snackId in
            return SignalProducer { observer, _ in
                // The sales magic happens here.
                // Fetch a snack based on its id
            }
        }

        // The sales recorders are notified for any successful sales.
        purchase.values.observeValues(salesRecorder.record)
    }
}
```

#### References

For more details about the concepts and primitives in ReactiveSwift, check these documentations out:

1. **[Framework Overview][]**

   An overview of the behaviors and the suggested use cases of the ReactiveSwift primitives and utilities.

1. **[Basic Operators][]**

   An overview of the operators provided to compose and transform these primitives.

1. **[Design Guidelines][]**

   Contracts of the ReactiveSwift primitives, Best Practices with ReactiveSwift, and Guidelines on implementing custom operators.

## Example: online search

Let’s say you have a text field, and whenever the user types something into it,
you want to make a network request which searches for that query.

_Please note that the following examples use Cocoa extensions in [ReactiveCocoa][] for illustration._

#### Observing text edits

The first step is to observe edits to the text field, using a RAC extension to
`UITextField` specifically for this purpose:

```swift
let searchStrings = textField.reactive.continuousTextValues
```

This gives us a [Signal][] which sends values of type `String?`.

#### Making network requests

With each string, we want to execute a network request. ReactiveSwift offers an
`URLSession` extension for doing exactly that:

```swift
let searchResults = searchStrings
    .flatMap(.latest) { (query: String?) -> SignalProducer<(Data, URLResponse), AnyError> in
        let request = self.makeSearchRequest(escapedQuery: query)
        return URLSession.shared.reactive.data(with: request)
    }
    .map { (data, response) -> [SearchResult] in
        let string = String(data: data, encoding: .utf8)!
        return self.searchResults(fromJSONString: string)
    }
    .observe(on: UIScheduler())
```

This has transformed our producer of `String`s into a producer of `Array`s
containing the search results, which will be forwarded on the main thread
(using the [`UIScheduler`][Schedulers]).

Additionally, [`flatMap(.latest)`][flatMapLatest] here ensures that _only one search_—the
latest—is allowed to be running. If the user types another character while the
network request is still in flight, it will be cancelled before starting a new
one. Just think of how much code that would take to do by hand!

#### Receiving the results

Since the source of search strings is a `Signal` which has a hot signal semantic,
the transformations we applied are automatically evaluated whenever new values are
emitted from `searchStrings`.

Therefore, we can simply observe the signal using `Signal.observe(_:)`:

```swift
searchResults.observe { event in
    switch event {
    case let .value(results):
        print("Search results: \(results)")

    case let .failed(error):
        print("Search error: \(error)")

    case .completed, .interrupted:
        break
    }
}
```

Here, we watch for the `Value` [event][Events], which contains our results, and
just log them to the console. This could easily do something else instead, like
update a table view or a label on screen.

#### Handling failures

In this example so far, any network error will generate a `Failed`
[event][Events], which will terminate the event stream. Unfortunately, this
means that future queries won’t even be attempted.

To remedy this, we need to decide what to do with failures that occur. The
quickest solution would be to log them, then ignore them:

```swift
    .flatMap(.latest) { (query: String) -> SignalProducer<(Data, URLResponse), AnyError> in
        let request = self.makeSearchRequest(escapedQuery: query)

        return URLSession.shared.reactive
            .data(with: request)
            .flatMapError { error in
                print("Network error occurred: \(error)")
                return SignalProducer.empty
            }
    }
```

By replacing failures with the `empty` event stream, we’re able to effectively
ignore them.

However, it’s probably more appropriate to retry at least a couple of times
before giving up. Conveniently, there’s a [`retry`][retry] operator to do exactly that!

Our improved `searchResults` producer might look like this:

```swift
let searchResults = searchStrings
    .flatMap(.latest) { (query: String) -> SignalProducer<(Data, URLResponse), AnyError> in
        let request = self.makeSearchRequest(escapedQuery: query)

        return URLSession.shared.reactive
            .data(with: request)
            .retry(upTo: 2)
            .flatMapError { error in
                print("Network error occurred: \(error)")
                return SignalProducer.empty
            }
    }
    .map { (data, response) -> [SearchResult] in
        let string = String(data: data, encoding: .utf8)!
        return self.searchResults(fromJSONString: string)
    }
    .observe(on: UIScheduler())
```

#### Throttling requests

Now, let’s say you only want to actually perform the search periodically,
to minimize traffic.

ReactiveCocoa has a declarative `throttle` operator that we can apply to our
search strings:

```swift
let searchStrings = textField.reactive.continuousTextValues
    .throttle(0.5, on: QueueScheduler.main)
```

This prevents values from being sent less than 0.5 seconds apart.

To do this manually would require significant state, and end up much harder to
read! With ReactiveCocoa, we can use just one operator to incorporate _time_ into
our event stream.

#### Debugging event streams

Due to its nature, a stream's stack trace might have dozens of frames, which, more often than not, can make debugging a very frustrating activity.
A naive way of debugging, is by injecting side effects into the stream, like so:

```swift
let searchString = textField.reactive.continuousTextValues
    .throttle(0.5, on: QueueScheduler.main)
    .on(event: { print ($0) }) // the side effect
```

This will print the stream's [events][Events], while preserving the original stream behaviour. Both [`SignalProducer`][SignalProducer]
and [`Signal`][Signal] provide the `logEvents` operator, that will do this automatically for you:

```swift
let searchString = textField.reactive.continuousTextValues
    .throttle(0.5, on: QueueScheduler.main)
    .logEvents()
```

For more information and advance usage, check the [Debugging Techniques](Documentation/DebuggingTechniques.md) document.

## How does ReactiveSwift relate to RxSwift?
RxSwift is a Swift implementation of the [ReactiveX][] (Rx) APIs. While ReactiveCocoa
was inspired and heavily influenced by Rx, ReactiveSwift is an opinionated
implementation of [functional reactive programming][], and _intentionally_ not a
direct port like [RxSwift][].

ReactiveSwift differs from RxSwift/ReactiveX where doing so:

 * Results in a simpler API
 * Addresses common sources of confusion
 * Matches closely to Swift, and sometimes Cocoa, conventions

The following are a few important differences, along with their rationales.

### Signals and SignalProducers (“hot” and “cold” observables)

One of the most confusing aspects of Rx is that of [“hot”, “cold”, and “warm”
observables](http://www.introtorx.com/content/v1.0.10621.0/14_HotAndColdObservables.html) (event streams).

In short, given just a method or function declaration like this, in C#:

```csharp
IObservable<string> Search(string query)
```

… it is **impossible to tell** whether subscribing to (observing) that
`IObservable` will involve side effects. If it _does_ involve side effects, it’s
also impossible to tell whether _each subscription_ has a side effect, or if only
the first one does.

This example is contrived, but it demonstrates **a real, pervasive problem**
that makes it extremely hard to understand Rx code (and pre-3.0 ReactiveCocoa
code) at a glance.

**ReactiveSwift** addresses this by distinguishing side effects with the separate
[`Signal`][Signal] and [`SignalProducer`][SignalProducer] types. Although this
means there’s another type to learn about, it improves code clarity and helps
communicate intent much better.

In other words, **ReactiveSwift’s changes here are [simple, not
easy](http://www.infoq.com/presentations/Simple-Made-Easy)**.

### Typed errors

When [Signals][Signal] and [SignalProducers][SignalProducer] are allowed to [fail][Events] in ReactiveSwift,
the kind of error must be specified in the type system. For example,
`Signal<Int, AnyError>` is a signal of integer values that may fail with an error
of type `AnyError`.

More importantly, RAC allows the special type `NoError` to be used instead,
which _statically guarantees_ that an event stream is not allowed to send a
failure. **This eliminates many bugs caused by unexpected failure events.**

In Rx systems with types, event streams only specify the type of their
values—not the type of their errors—so this sort of guarantee is impossible.

### Naming

In most versions of Rx, Streams over time are known as `Observable`s, which
parallels the `Enumerable` type in .NET. Additionally, most operations in Rx.NET
borrow names from [LINQ](https://msdn.microsoft.com/en-us/library/bb397926.aspx),
which uses terms reminiscent of relational databases, like `Select` and `Where`.

**ReactiveSwift**, on the other hand, focuses on being a native Swift citizen
first and foremost, following the [Swift API Guidelines][] as appropriate. Other
naming differences are typically inspired by significantly better alternatives
from [Haskell](https://www.haskell.org) or [Elm](http://elm-lang.org) (which is the primary source for the “signal” terminology).

### UI programming

Rx is basically agnostic as to how it’s used. Although UI programming with Rx is
very common, it has few features tailored to that particular case.

ReactiveSwift takes a lot of inspiration from [ReactiveUI](http://reactiveui.net/),
including the basis for [Actions][].

Unlike ReactiveUI, which unfortunately cannot directly change Rx to make it more
friendly for UI programming, **ReactiveSwift has been improved many times
specifically for this purpose**—even when it means diverging further from Rx.

## Getting started

ReactiveSwift supports macOS 10.9+, iOS 8.0+, watchOS 2.0+, tvOS 9.0+ and Linux.

#### Carthage

If you use [Carthage][] to manage your dependencies, simply add
ReactiveSwift to your `Cartfile`:

```
github "ReactiveCocoa/ReactiveSwift" ~> 1.1
```

If you use Carthage to build your dependencies, make sure you have added `ReactiveSwift.framework`, and `Result.framework` to the "_Linked Frameworks and Libraries_" section of your target, and have included them in your Carthage framework copying build phase.

#### CocoaPods

If you use [CocoaPods][] to manage your dependencies, simply add
ReactiveSwift to your `Podfile`:

```
pod 'ReactiveSwift', '~> 1.1'
```

#### Swift Package Manager

If you use Swift Package Manager, simply add ReactiveSwift as a dependency
of your package in `Package.swift`:

```
.Package(url: "https://github.com/ReactiveCocoa/ReactiveSwift.git", majorVersion: 1)
```

#### Git submodule

 1. Add the ReactiveSwift repository as a [submodule][] of your
    application’s repository.
 1. Run `git submodule update --init --recursive` from within the ReactiveCocoa folder.
 1. Drag and drop `ReactiveSwift.xcodeproj` and
    `Carthage/Checkouts/Result/Result.xcodeproj` into your application’s Xcode
    project or workspace.
 1. On the “General” tab of your application target’s settings, add
    `ReactiveSwift.framework`, and `Result.framework`
    to the “Embedded Binaries” section.
 1. If your application target does not contain Swift code at all, you should also
    set the `EMBEDDED_CONTENT_CONTAINS_SWIFT` build setting to “Yes”.

## Playground

We also provide a great Playground, so you can get used to ReactiveCocoa's operators. In order to start using it:

 1. Clone the ReactiveSwift repository.
 1. Retrieve the project dependencies using one of the following terminal commands from the ReactiveSwift project root directory:
     - `git submodule update --init --recursive` **OR**, if you have [Carthage][] installed    
     - `carthage checkout`
 1. Open `ReactiveSwift.xcworkspace`
 1. Build `Result-Mac` scheme
 1. Build `ReactiveSwift-macOS` scheme
 1. Finally open the `ReactiveSwift.playground`
 1. Choose `View > Show Debug Area`

## Have a question?
If you need any help, please visit our [GitHub issues][] or [Stack Overflow][]. Feel free to file an issue if you do not manage to find any solution from the archives.

## Release Roadmap
**Current Stable Release:**<br />[![GitHub release](https://img.shields.io/github/release/ReactiveCocoa/ReactiveSwift.svg)](https://github.com/ReactiveCocoa/ReactiveSwift/releases)

### Plan of Record
#### ReactiveSwift 2.0
It targets Swift 3.1.x. The estimated schedule is Spring 2017.

The release contains breaking changes. But they are not expected to affect the general mass of users, but only a few specific use cases.

The primary goal of ReactiveSwift 2.0 is to adopt **concrete same-type requirements**, and remove as many single-implementation protocols as possible.

ReactiveSwift 2.0 may include other proposed breaking changes.

As Swift 4.0 introduces library evolution and resilience, it is important for us to have a clean and steady API to start with. The expectation is to **have the API cleanup and the reviewing to be concluded in ReactiveSwift 2.0**, before we move on to ReactiveSwift 3.0 and Swift 4.0. Any contribution to help realising this goal is welcomed.

#### ReactiveSwift 3.0
It targets Swift 4.0.x. The estimated schedule is late 2017.

The release may contain breaking changes, depending on what features are being delivered by Swift 4.0.

ReactiveSwift 3.0 would focus on two main goals:

1. Swift 4.0 Library Evolution and Resilience
2. Adapt to new features introduced in Swift 4.0 Phase 2.

[ReactiveCocoa]: https://github.com/ReactiveCocoa/ReactiveCocoa/#readme
[Actions]: Documentation/FrameworkOverview.md#actions
[Basic Operators]: Documentation/BasicOperators.md
[Design Guidelines]: Documentation/DesignGuidelines.md
[Carthage]: https://github.com/Carthage/Carthage/#readme
[CocoaPods]: https://cocoapods.org/
[CHANGELOG]: CHANGELOG.md
[Code]: Sources
[Documentation]: Documentation
[Events]: Documentation/FrameworkOverview.md#events
[Framework Overview]: Documentation/FrameworkOverview.md
[Schedulers]: Documentation/FrameworkOverview.md#schedulers
[SignalProducer]: Documentation/FrameworkOverview.md#signal-producers
[Signal]: Documentation/FrameworkOverview.md#signals
[Swift API]: ReactiveCocoa/Swift
[flatMapLatest]: Documentation/BasicOperators.md#switching-to-the-latest
[retry]: Documentation/BasicOperators.md#retrying
[Looking for the Objective-C API?]: https://github.com/ReactiveCocoa/ReactiveObjC/#readme
[Still using Swift 2.x?]: https://github.com/ReactiveCocoa/ReactiveCocoa/tree/v4.0.0
[GitHub issues]: https://github.com/ReactiveCocoa/ReactiveSwift/issues?q=is%3Aissue+label%3Aquestion+
[Stack Overflow]: http://stackoverflow.com/questions/tagged/reactive-cocoa
[submodule]: https://git-scm.com/docs/git-submodule
[functional reactive programming]: https://en.wikipedia.org/wiki/Functional_reactive_programming
[ReactiveX]: https://reactivex.io/
[RxSwift]: https://github.com/ReactiveX/RxSwift/#readme
[Swift API Guidelines]: https://swift.org/documentation/api-design-guidelines/
