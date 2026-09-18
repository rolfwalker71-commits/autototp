// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Autototp",
    defaultLocalization: "de",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Autototp", targets: ["Autototp"]),
    ],
    targets: [
        .target(
            name: "AutototpCore",
            path: "Sources/AutototpCore"
        ),
        .executableTarget(
            name: "Autototp",
            dependencies: ["AutototpCore"],
            path: "Sources/Autototp",
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(
            name: "AutototpCoreTests",
            dependencies: ["AutototpCore"],
            path: "Tests/AutototpCoreTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
