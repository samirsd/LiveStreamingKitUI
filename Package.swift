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
            .package(url: "https://github.com/samirsd/LiveStreamingKit.git", from: "0.1.0"),
        useLocalDependencies ?
            .package(path: "../LoggingKit") :
            .package(url: "https://github.com/samirsd/LoggingKit.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "LiveStreamingKitUI",
            dependencies: ["LiveStreamingKit", "LoggingKit"]
        ),
        .testTarget(
            name: "LiveStreamingKitUITests",
            dependencies: ["LiveStreamingKitUI"]
        ),
    ]
)
