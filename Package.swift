// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NerdFonter",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "NerdFonter", dependencies: ["NerdFonterKit"]),
        .target(name: "NerdFonterKit"),
        .testTarget(name: "NerdFonterKitTests", dependencies: ["NerdFonterKit"]),
    ]
)
