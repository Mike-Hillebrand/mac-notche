// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacNotche",
    platforms: [.macOS("14.2")],
    targets: [
        .executableTarget(
            name: "MacNotche",
            path: "Sources/MacNotche",
            linkerSettings: [.linkedFramework("IOBluetooth")]
        )
    ]
)
