# ReactiveSwift

#### Streams of values over time. Tailored for Swift.

[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](#carthage) [![CocoaPods compatible](https://img.shields.io/cocoapods/v/ReactiveSwift.svg)](#cocoapods) [![GitHub release](https://img.shields.io/github/release/ReactiveCocoa/ReactiveCocoa.svg)](https://github.com/ReactiveCocoa/ReactiveCocoa/releases) ![Swift 3.0.x](https://img.shields.io/badge/Swift-3.0.x-orange.svg) ![platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20OS%20X%20%7C%20watchOS%20%7C%20tvOS%20-lightgrey.svg)

⚠️ [Looking for the Objective-C API?][] ⚠️ [Still using Swift 2.x?][]
🎉 [Getting Started](#getting-started)

## What is ReactiveSwift?
__ReactiveSwift__ offers composable, declaractive and flexible primitives that are built around the grand concept of ___streams of values over time___. These primitives can be used to uniformly represent common Cocoa and generic programming patterns that are fundementally an act of observation, e.g.:

 * Delegate methods
 * Callback blocks
 * Notifications
 * Control actions and responder chain events
 * [Futures and promises](https://en.wikipedia.org/wiki/Futures_and_promises)
 * [Key-value observing](https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/KeyValueObserving/KeyValueObserving.html) (KVO)

Because all of these different mechanisms can be represented in the _same_ way,
it’s easy to declaratively chain and combine them together, with less spaghetti
code and state to bridge the gap.

For more information about the concepts in ReactiveSwift, see the [Framework
Overview][].

## Looking for Cocoa extensions?
See [ReactiveCocoa][], which hosts Cocoa extensions built on top of ReactiveSwift.

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

This gives us a [Signal][Signals] which sends values of type `String?`.

#### Making network requests

With each string, we want to execute a network request. ReactiveSwift offers an
`URLSession` extension for doing exactly that:

```swift
let searchResults = searchStrings
    .flatMap(.latest) { (query: String?) -> SignalProducer<(Data, URLResponse), NSError> in
        let request = self.makeSearchRequest(escapedQuery: query)
        return URLSession.shared.reactive.data(with: request)
    }
    .map { (data, response) -> [SearchResult] in
        let string = String(data: data, encoding: .utf8)!
        return self.searchResults(fromJsonString: string)
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
emitted from `searchString`.

Therefore, we can simply observe the signal using `Signal.observe(_:)`:

```swift
searchResults.observe { event in
    switch event {
    case let .value(results):
        print("Search results: \(results)")
        
    case let .error(error):
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
    .flatMap(.latest) { (query: String) -> SignalProducer<(Data, URLResponse), NSError> in
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
    .flatMap(.latest) { (query: String) -> SignalProducer<(Data, URLResponse), NSError> in
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
        return self.searchResults(fromJsonString: string)
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

This will print the stream's [events][Events], while preserving the original stream behaviour. Both [`SignalProducer`][Signal producers]
and [`Signal`][Signals] provide the `logEvents` operator, that will do this automatically for you:

```swift
let searchString = textField.reactive.continuousTextValues
    .throttle(0.5, on: QueueScheduler.main)
    .logEvents()
```

For more information and advance usage, check the [Debugging Techniques](Documentation/DebuggingTechniques.md) document.

## How does ReactiveSwift relate to Rx?

ReactiveCocoa was originally inspired, and therefore heavily influenced, by
Microsoft’s [Reactive
Extensions](https://msdn.microsoft.com/en-us/data/gg577609.aspx) (Rx) library. There are many ports of Rx, including [RxSwift](https://github.com/ReactiveX/RxSwift), but ReactiveCocoa is _intentionally_ not a direct port.

**Where ReactiveSwift differs from Rx**, it is usually to:

 * Create a simpler API
 * Address common sources of confusion
 * More closely match Cocoa conventions

The following are some of the concrete differences, along with their rationales.

### Naming

In most versions of Rx, Streams over time are known as `Observable`s, which
parallels the `Enumerable` type in .NET. Additionally, most operations in Rx.NET
borrow names from [LINQ](https://msdn.microsoft.com/en-us/library/bb397926.aspx),
which uses terms reminiscent of relational databases, like `Select` and `Where`.

**RAC is focused on matching Swift naming first and foremost**, with terms like
`map` and `filter` instead. Other naming differences are typically inspired by
significantly better alternatives from [Haskell](https://www.haskell.org) or
[Elm](http://elm-lang.org) (which is the primary source for the “signal”
terminology).

### Signals and Signal Producers (“hot” and “cold” observables)

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

[ReactiveCocoa 3.0][https://github.com/ReactiveCocoa/ReactiveCocoa/blob/master/CHANGELOG.md] has solved this problem by distinguishing side
effects with the separate [`Signal`][Signals] and [`SignalProducer`][Signal producers] types. Although this
means there’s another type to learn about, it improves code clarity and helps
communicate intent much better.

In other words, **ReactiveSwift’s changes here are [simple, not
easy](http://www.infoq.com/presentations/Simple-Made-Easy)**.

### Typed errors

When [signals][] and [signal producers][] are allowed to [fail][Events] in ReactiveSwift,
the kind of error must be specified in the type system. For example,
`Signal<Int, NSError>` is a signal of integer values that may fail with an error
of type `NSError`.

More importantly, RAC allows the special type `NoError` to be used instead,
which _statically guarantees_ that an event stream is not allowed to send a
failure. **This eliminates many bugs caused by unexpected failure events.**

In Rx systems with types, event streams only specify the type of their
values—not the type of their errors—so this sort of guarantee is impossible.

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

If you are using [Carthage][] to manage your dependency, simply add
ReactiveSwift to your `Cartfile`:

```
github "ReactiveCocoa/ReactiveSwift"
```

If you use Carthage to build your dependencies, make sure you have added `ReactiveSwift.framework`, and `Result.framework` to the "_Linked Frameworks and Libraries_" section of your target, and have included them in your Carthage framework copying build phase.

#### CocoaPods

If you are using [CocoaPods][] to manage your dependency, simply add
ReactiveSwift to your `Podfile`:

```
pod 'ReactiveSwift', :git => 'https://github.com/ReactiveCocoa/ReactiveSwift.git'
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
     - `git submodule update --init --recursive` **OR**, if you have [Carthage](https://github.com/Carthage/Carthage) installed    
     - `carthage checkout`
 1. Open `ReactiveSwift.xcworkspace`
 1. Build `Result-Mac` scheme
 1. Build `ReactiveSwift-macOS` scheme
 1. Finally open the `ReactiveSwift.playground`
 1. Choose `View > Show Debug Area`
 
## Have a question?
If you need any help, please visit our [GitHub issues][] or [Stack Overflow][]. Feel free to file an issue if you do not manage to find any solution from the archives.

[ReactiveCocoa]: https://github.com/ReactiveCocoa/ReactiveCocoa/#readme
[Actions]: Documentation/FrameworkOverview.md#actions
[Basic Operators]: Documentation/BasicOperators.md
[CHANGELOG]: CHANGELOG.md
[Code]: Sources
[Documentation]: Documentation
[Events]: Documentation/FrameworkOverview.md#events
[Framework Overview]: Documentation/FrameworkOverview.md
[Schedulers]: Documentation/FrameworkOverview.md#schedulers
[Signal producers]: Documentation/FrameworkOverview.md#signal-producers
[Signals]: Documentation/FrameworkOverview.md#signals
[Swift API]: ReactiveCocoa/Swift
[flatMapLatest]: Documentation/BasicOperators.md#switching-to-the-latest
[retry]: Documentation/BasicOperators.md#retrying
[Looking for the Objective-C API?]: https://github.com/ReactiveCocoa/ReactiveObjC/#readme
[Still using Swift 2.x?]: https://github.com/ReactiveCocoa/ReactiveCocoa/tree/v4.0.0
[GitHub issues]: https://github.com/ReactiveCocoa/ReactiveSwift/issues?q=is%3Aissue+label%3Aquestion+
[Stack Overflow]: http://stackoverflow.com/questions/tagged/reactive-cocoa
[functional reactive programming]: https://en.wikipedia.org/wiki/Functional_reactive_programming
