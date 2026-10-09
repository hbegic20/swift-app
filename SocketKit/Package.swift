// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SocketKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SocketKit", targets: ["SocketKit"]),
    ],
    targets: [
        .target(name: "SocketKit"),
        .testTarget(name: "SocketKitTests", dependencies: ["SocketKit"]),
    ]
)
