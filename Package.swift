// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DriveScanner",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "DriveScannerCore", targets: ["DriveScannerCore"]),
        .library(name: "DriveScannerUI", targets: ["DriveScannerUI"]),
        .executable(name: "DriveScanner", targets: ["DriveScannerApp"]),
    ],
    targets: [
        .target(
            name: "DriveScannerCore",
            path: "Sources/DriveScannerCore"
        ),
        .target(
            name: "DriveScannerUI",
            dependencies: ["DriveScannerCore"],
            path: "Sources/DriveScannerUI"
        ),
        .executableTarget(
            name: "DriveScannerApp",
            dependencies: ["DriveScannerUI"],
            path: "Sources/DriveScannerApp"
        ),
        .testTarget(
            name: "DriveScannerTests",
            dependencies: ["DriveScannerCore"],
            path: "Tests/DriveScannerTests"
        ),
    ]
)
