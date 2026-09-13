// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Baram",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Baram", targets: ["Baram"])],
    targets: [
        .executableTarget(name: "Baram"),
        .testTarget(name: "BaramTests", dependencies: ["Baram"])
    ],
    swiftLanguageModes: [.v5]
)
