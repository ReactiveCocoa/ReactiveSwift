import PackageDescription

let package = Package(
    name: "ReactiveSwift",
    targets: [
        Target(name: "ReactiveSwift", dependencies: ["OSLocking"]),
        Target(name: "OSLocking")
    ],
    dependencies: [
        .Package(url: "https://github.com/antitypical/Result.git", versions: Version(3, 1, 0)..<Version(3, .max, .max)),
    ]
)
