import SwiftUI
import WebKit

/// Embedded browser surface for the in-world browser window.
/// YouTube playback uses the normal website player; DRM/airplay/fullscreen
/// behavior remains subject to WebKit and YouTube's current policies.
public struct PopinVRBrowserWindow: UIViewRepresentable {
    public let initialURL: URL
    public var onNavigationFailure: ((String) -> Void)?

    public init(
        initialURL: URL = URL(string: "https://www.youtube.com")!,
        onNavigationFailure: ((String) -> Void)? = nil
    ) {
        self.initialURL = initialURL
        self.onNavigationFailure = onNavigationFailure
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onNavigationFailure: onNavigationFailure)
    }

    public func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.isScrollEnabled = true
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.load(URLRequest(url: initialURL))
        return webView
    }

    public func updateUIView(_ webView: WKWebView, context: Context) {}

    public final class Coordinator: NSObject, WKNavigationDelegate {
        private let onNavigationFailure: ((String) -> Void)?
        init(onNavigationFailure: ((String) -> Void)?) {
            self.onNavigationFailure = onNavigationFailure
        }

        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onNavigationFailure?(error.localizedDescription)
        }

        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onNavigationFailure?(error.localizedDescription)
        }
    }
}
