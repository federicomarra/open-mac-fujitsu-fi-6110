// swift-tools-version:5.9
import PackageDescription

// The SANE fujitsu backend module and libusb (built by vendor/build-sane.sh)
// are loaded at runtime with dlopen — nothing to link here. ScannerCore is told
// where they live: vendor/out/lib during development, Contents/Frameworks in the app.
let package = Package(
    name: "FiScanner",
    defaultLocalization: "en",
    platforms: [.macOS(.v12)],
    targets: [
        .target(name: "CSane"),
        .target(
            name: "ScannerCore",
            dependencies: ["CSane"]
        ),
        .executableTarget(
            name: "SaneHarness",
            dependencies: ["ScannerCore"]
        ),
        .executableTarget(
            name: "FiScanner",
            dependencies: ["ScannerCore"],
            resources: [.process("Resources")]
        ),
    ]
)
