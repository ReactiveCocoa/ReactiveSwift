import PackageDescription

let package = Package(
    name: "ReactiveSwift",
    targets: [
        Target(name: "ReactiveSwift", dependencies: ["OSLocking"]),
        Target(name: "OSLocking")
    ],
    dependencies: [
        .Package(url: "https://github.com/antitypical/Result.git", versions: Version(3, 1, 0)..<Version(3, .max, .max)),
        .Package(url: "https://github.com/Quick/Quick", majorVersion: 1, minor: 1),
        .Package(url: "https://github.com/Quick/Nimble", majorVersion: 6),
    ]
)
