// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "WaltzAssistant", platforms: [.macOS(.v14)],
    products: [.executable(name: "WaltzAssistant", targets: ["WaltzAssistant"]), .executable(name: "WaltzInspect", targets: ["WaltzInspect"])],
    targets: [
        .target(name: "WaltzCore", resources: [.process("Resources")]),
        .executableTarget(name: "WaltzAssistant", dependencies: ["WaltzCore"]),
        .executableTarget(name: "WaltzInspect", dependencies: ["WaltzCore"]),
        .executableTarget(name: "WaltzTests", dependencies: ["WaltzCore"], path: "Tests/WaltzCoreTests")
    ]
)
