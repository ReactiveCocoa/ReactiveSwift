// swift-tools-version:5.0
import PackageDescription
import class Foundation.ProcessInfo

let shouldTest = ProcessInfo.processInfo.environment["TEST"] == "1"

func resolveDependencies() -> [Package.Dependency] {
    guard shouldTest else { return [] }

    return [
        .package(url: "https://github.com/Quick/Quick.git", from: "2.0.0"),
        .package(url: "https://github.com/Quick/Nimble.git", from: "8.0.0"),
    ]
}

func resolveTargets() -> [Target] {
    let baseTarget = Target.target(name: "ReactiveSwift", dependencies: [], path: "Sources")
    let testTarget = Target.testTarget(name: "ReactiveSwiftTests", dependencies: ["ReactiveSwift", "Quick", "Nimble"])

    return shouldTest ? [baseTarget, testTarget] : [baseTarget]
}

let package = Package(
    name: "ReactiveSwift",
    products: [
        .library(name: "ReactiveSwift", targets: ["ReactiveSwift"]),
    ],
    dependencies: resolveDependencies(),
    targets: resolveTargets(),
    swiftLanguageVersions: [.v5]
)
