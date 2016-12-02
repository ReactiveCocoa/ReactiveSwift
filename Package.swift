import PackageDescription

let package = Package(
    name: "ReactiveSwift",
    dependencies: [
        .Package(url: "https://github.com/antitypical/Result.git", versions: Version(3, 1, 0)..<Version(3, .max, .max)),
    ],
    exclude: [
        "Sources/Deprecations+Removals.swift",
    ]
)
