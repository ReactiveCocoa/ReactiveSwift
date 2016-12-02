import PackageDescription

let package = Package(
    name: "ReactiveSwift",
    dependencies: [
        .Package(url: "https://github.com/antitypical/Result.git", versions: Version(3, 1, 0)..<Version(3, .max, .max)),
        .Package(url: "https://github.com/Quick/Quick", majorVersion: 1),
        .Package(url: "https://github.com/Quick/Nimble", majorVersion: 5, minor: 1),
    ],
    exclude: [
        "Sources/Deprecations+Removals.swift",
    ]
)
