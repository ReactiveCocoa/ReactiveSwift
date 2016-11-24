import PackageDescription

let package = Package(
    name: "ReactiveSwift",
    dependencies: [
        .Package(url: "https://github.com/antitypical/Result.git", majorVersion: 3),
        .Package(url: "https://github.com/Quick/Quick", majorVersion: 1),
        .Package(url: "https://github.com/Quick/Nimble", majorVersion: 5, minor: 1),
    ],
    exclude: [
        "Sources/Deprecations+Removals.swift",
    ]
)
