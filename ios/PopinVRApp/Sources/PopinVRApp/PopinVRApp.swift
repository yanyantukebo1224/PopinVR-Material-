import SwiftUI
import PopinVRCore

@main
struct PopinVRApp: App {
    var body: some Scene {
        WindowGroup {
            PopinVRHeadsetView()
                .preferredColorScheme(.dark)
                .statusBarHidden()
        }
    }
}
