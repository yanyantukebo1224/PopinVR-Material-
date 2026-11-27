// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PopinVRCore",
    platforms: [.iOS(.v17)],
    products: [.library(name: "PopinVRCore", targets: ["PopinVRCore"])],
    targets: [
        .target(name: "PopinVRSOMA", path: "Sources/PopinVRSOMA", publicHeadersPath: "include"),
        .target(
            name: "PopinVRCore",
            dependencies: ["PopinVRSOMA"],
            path: "Sources/PopinVRCore",
            resources: [.process("Shaders")],
            linkerSettings: [.linkedFramework("ARKit"), .linkedFramework("Vision"), .linkedFramework("MetalKit"), .linkedFramework("CoreML"), .linkedFramework("AVFoundation"), .linkedFramework("UIKit"), .linkedFramework("SwiftUI"), .linkedFramework("CoreImage"), .linkedFramework("CoreGraphics")]
        )
    ]
)
