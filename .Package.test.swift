import PackageDescription

let package = Package(
    name: "ReactiveSwift",
    dependencies: [
        .Package(url: "https://github.com/antitypical/Result.git", versions: Version(3, 2, 1)..<Version(3, .max, .max)),
        .Package(url: "https://github.com/Quick/Quick", majorVersion: 1, minor: 1),
        .Package(url: "https://github.com/Quick/Nimble", majorVersion: 6, minor: 1),
    ]
)
