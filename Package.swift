import PackageDescription

let package = Package(
    name: "ReactiveSwift",
    dependencies: [
        .Package(url: "https://github.com/antitypical/Result.git", majorVersion: 3, minor: 0)
    ],
    exclude: [
        "Sources/Deprecations+Removals.swift",
    ]
)
