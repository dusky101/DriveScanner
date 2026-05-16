// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DriveScanner",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "DriveScanner", targets: ["DriveScanner"]),
    ],
    targets: [
        .target(
            name: "DriveScannerCore",
            path: "Sources/DriveScannerCore"
        ),
        .executableTarget(
            name: "DriveScanner",
            dependencies: ["DriveScannerCore"],
            path: "Sources/DriveScanner"
        ),
        .testTarget(
            name: "DriveScannerTests",
            dependencies: ["DriveScannerCore"],
            path: "Tests/DriveScannerTests"
        ),
    ]
)
