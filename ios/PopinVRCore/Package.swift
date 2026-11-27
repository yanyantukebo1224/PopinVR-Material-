// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PopinVRCore",
    platforms: [.iOS(.v17)],
    products: [.library(name: "PopinVRCore", targets: ["PopinVRCore"])],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19")
    ],
    targets: [
        .target(name: "PopinVRSOMA", path: "Sources/PopinVRSOMA", publicHeadersPath: "include"),
        .target(
            name: "PopinVRCore",
            dependencies: [
                "PopinVRSOMA",
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "Sources/PopinVRCore",
            resources: [.process("Shaders")],
            linkerSettings: [
                .linkedFramework("ARKit"),
                .linkedFramework("Vision"),
                .linkedFramework("MetalKit"),
                .linkedFramework("CoreML"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("UIKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreGraphics")
            ]
        )
    ]
)
