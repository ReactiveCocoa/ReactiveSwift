import XCTest
import Quick

@testable import ReactiveSwiftTests

Quick.QCKMain([
    ActionSpec.self,
    AtomicSpec.self,
    BagSpec.self,
    DisposableSpec.self,
    FlattenSpec.self,
    FoundationExtensionsSpec.self,
    LifetimeSpec.self,
    PropertySpec.self,
    SchedulerSpec.self,
    SignalLifetimeSpec.self,
    SignalProducerLiftingSpec.self,
    SignalProducerSpec.self,
    SignalSpec.self,
])
