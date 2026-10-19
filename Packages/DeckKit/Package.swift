// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "DeckKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "DeckKit", targets: ["DeckKit"]),
    ],
    targets: [
        .target(name: "DeckKit"),
        .testTarget(name: "DeckKitTests", dependencies: ["DeckKit"]),
    ]
)
