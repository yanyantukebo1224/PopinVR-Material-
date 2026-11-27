// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PopinVRCore",
    platforms: [.iOS(.v17)],
    products: [.library(name: "PopinVRCore", targets: ["PopinVRCore"])],
    targets: [
        .target(
            name: "PopinVRCore",
            path: "Sources/PopinVRCore",
            resources: [.process("Shaders")],
            linkerSettings: [.linkedFramework("ARKit"), .linkedFramework("Vision"), .linkedFramework("MetalKit"), .linkedFramework("CoreML")]
        )
    ]
)
