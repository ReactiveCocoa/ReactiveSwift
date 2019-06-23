// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "ReactiveSwift",
    platforms: [
       .watchOS(.v5), .iOS(.v8)
    ],
    products: [
        .library(name: "ReactiveSwift", targets: ["ReactiveSwift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Quick/Quick.git", from: "2.0.0"),
        .package(url: "https://github.com/Quick/Nimble.git", from: "8.0.0"),
    ],
    targets: [
        .target(name: "ReactiveSwift", dependencies: [], path: "Sources"),
        .testTarget(name: "ReactiveSwiftTests", dependencies: ["ReactiveSwift", "Quick", "Nimble"]),
    ],
    swiftLanguageVersions: [.v5]
)
