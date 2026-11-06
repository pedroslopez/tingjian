// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
    // AVFoundation / Core Audio types aren't Sendable-annotated; keep Swift 5 mode
    // so the audio plumbing stays readable.
    .swiftLanguageMode(.v5),
]

let package = Package(
    name: "tingjian",
    platforms: [.macOS("26.4")],
    products: [
        .executable(name: "tingjian", targets: ["Tingjian"]),
        .executable(name: "tingjian-cli", targets: ["tingjian-cli"]),
    ],
    targets: [
        .target(name: "TingjianCore", swiftSettings: settings),
        .executableTarget(name: "Tingjian", dependencies: ["TingjianCore"], swiftSettings: settings),
        .executableTarget(name: "tingjian-cli", dependencies: ["TingjianCore"], swiftSettings: settings),
    ]
)
