// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SocketKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SocketKit", targets: ["SocketKit"]),
        .library(name: "SocketKitSupabase", targets: ["SocketKitSupabase"]),
    ],
    dependencies: [
        // Only SocketKitSupabase uses it. SocketKit itself stays dependency-free.
        .package(url: "https://github.com/supabase/supabase-swift", from: "2.55.3"),
    ],
    targets: [
        .target(name: "SocketKit"),
        .testTarget(name: "SocketKitTests", dependencies: ["SocketKit"]),

        // The Supabase backend: transport and catch-up behind SocketKit's protocols.
        .target(
            name: "SocketKitSupabase",
            dependencies: [
                "SocketKit",
                .product(name: "Supabase", package: "supabase-swift"),
            ]
        ),
        .testTarget(name: "SocketKitSupabaseTests", dependencies: ["SocketKitSupabase"]),
    ]
)
