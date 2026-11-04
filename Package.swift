// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "MemoLine", platforms: [.macOS(.v14)],
    products: [.executable(name: "MemoLine", targets: ["MemoLine"])],
    targets: [
        .target(name: "MemoCore"),
        .executableTarget(name: "MemoLine", dependencies: ["MemoCore"]),
        .executableTarget(name: "MemoCoreTests", dependencies: ["MemoCore"], path: "Tests/MemoCoreTests")
    ]
)
