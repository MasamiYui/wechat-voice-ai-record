// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WeChatVoiceRecorder",
    platforms: [
        .macOS(.v13) // ScreenCaptureKit audio capture requires macOS 13.0+
    ],
    products: [
        .executable(name: "WeChatVoiceRecorder", targets: ["WeChatVoiceRecorder"])
    ],
    dependencies: [
        .package(url: "https://github.com/aliyun/alibabacloud-oss-swift-sdk-v2.git", from: "0.1.0-beta"),
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.14.1")
    ],
    targets: [
        .executableTarget(
            name: "WeChatVoiceRecorder",
            dependencies: [
                .product(name: "AlibabaCloudOSS", package: "alibabacloud-oss-swift-sdk-v2"),
                .product(name: "SQLite", package: "SQLite.swift")
            ],
            path: "Sources/WeChatVoiceRecorder",
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
