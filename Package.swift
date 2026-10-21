// swift-tools-version: 6.0
import Foundation
import PackageDescription

let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let isLocalPackagesWorkspace = packageDirectory.deletingLastPathComponent().lastPathComponent == "packages"
let hasLocalLiveStreamingKit = isLocalPackagesWorkspace && ["LiveStreamingKit", "LoggingKit"].allSatisfy { packageName in
    FileManager.default.fileExists(
        atPath: packageDirectory
            .appendingPathComponent("../\(packageName)/Package.swift")
            .standardizedFileURL.path
    )
}
let useLocalDependencies =
    ProcessInfo.processInfo.environment["USE_LOCAL_PACKAGES"] == "1" ||
    hasLocalLiveStreamingKit
let hasLocalFontKit = isLocalPackagesWorkspace && FileManager.default.fileExists(
    atPath: packageDirectory.appendingPathComponent("../FontKit/Package.swift").standardizedFileURL.path
)

let package = Package(
    name: "LiveStreamingKitUI",
    platforms: [
        .iOS("18.0"),
        .macOS("14.0")
    ],
    products: [
        .library(
            name: "LiveStreamingKitUI",
            targets: ["LiveStreamingKitUI"]
        ),
    ],
    dependencies: [
        useLocalDependencies ?
            .package(path: "../LiveStreamingKit") :
            .package(url: "https://github.com/samirsd/LiveStreamingKit.git", revision: "3323bd926011a4dd085301420d7563e310cfb5ce"),
        useLocalDependencies ?
            .package(path: "../LoggingKit") :
            .package(url: "https://github.com/samirsd/LoggingKit.git", from: "1.0.11"),
        hasLocalFontKit ?
            .package(path: "../FontKit") :
            .package(url: "https://github.com/samirsd/FontKit.git", from: "1.0.11"),
    ],
    targets: [
        .target(
            name: "LiveStreamingKitUI",
            dependencies: ["LiveStreamingKit", "LoggingKit", "FontKit"]
        ),
        .testTarget(
            name: "LiveStreamingKitUITests",
            dependencies: ["LiveStreamingKitUI"]
        ),
    ]
)
