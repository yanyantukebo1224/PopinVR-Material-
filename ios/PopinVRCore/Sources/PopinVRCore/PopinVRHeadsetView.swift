import SwiftUI

/// SwiftUI entry point for the native split-screen headset smoke test.
public struct PopinVRHeadsetView: UIViewControllerRepresentable {
    public init() {}

    public func makeUIViewController(context: Context) -> PopinVRHeadsetViewController {
        PopinVRHeadsetViewController()
    }

    public func updateUIViewController(_ controller: PopinVRHeadsetViewController, context: Context) {}
}
