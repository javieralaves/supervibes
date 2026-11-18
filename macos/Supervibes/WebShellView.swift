import AppKit
import SwiftUI
import WebKit

/// The main window's content while screens are still web: the Supervibes web app in a WKWebView,
/// with native states for when the server can't be reached or sign-in can't happen in-app.
struct WebShellView: View {
    @State private var model = WebShellModel(baseURL: AppConfig.baseURL)

    var body: some View {
        WebViewHost(webView: model.webView)
            .overlay {
                switch model.status {
                case .loading, .ready:
                    EmptyView()
                case .unreachable(let reason):
                    ContentUnavailableView {
                        Label("Can't reach Supervibes", systemImage: "network.slash")
                    } description: {
                        Text("Nothing answered at \(model.baseURL.absoluteString). \(reason)")
                    } actions: {
                        Button("Try Again") { model.load() }
                            .keyboardShortcut(.defaultAction)
                    }
                    .background(.background)
                case .signInUnavailable:
                    ContentUnavailableView {
                        Label("Sign-in isn't wired up yet", systemImage: "person.badge.key")
                    } description: {
                        Text("Google doesn't allow signing in inside an app's embedded web view. Native sign-in comes with the API work.")
                    } actions: {
                        Button("Back") { model.load() }
                    }
                    .background(.background)
                }
            }
            .task { model.load() }
    }
}

@MainActor
@Observable
final class WebShellModel: NSObject {
    enum Status: Equatable {
        case loading
        case ready
        case unreachable(String)
        case signInUnavailable
    }

    private(set) var status: Status = .loading
    let baseURL: URL

    @ObservationIgnored
    lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        #if DEBUG
        // Lets Safari's Web Inspector attach (Develop menu → this Mac → Supervibes).
        view.isInspectable = true
        #endif
        return view
    }()

    init(baseURL: URL) {
        self.baseURL = baseURL
        super.init()
    }

    func load() {
        status = .loading
        Log.web.info("Loading \(self.baseURL.absoluteString, privacy: .public)")
        webView.load(URLRequest(url: baseURL))
    }

    fileprivate func failed(_ error: any Error) {
        let error = error as NSError
        // Cancelled loads (including ones we cancel on purpose) aren't failures.
        if error.code == NSURLErrorCancelled || (error.domain == "WebKitErrorDomain" && error.code == 102) {
            return
        }
        Log.web.error("Load failed: \(error.localizedDescription, privacy: .public)")
        let hint = baseURL.host() == "localhost" ? "Start it with `npm run dev`, then try again." : error.localizedDescription
        status = .unreachable(hint)
    }
}

extension WebShellModel: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.request.url?.host() == "accounts.google.com" {
            Log.web.notice("Stopped Google sign-in, which embedded web views can't do")
            status = .signInUnavailable
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        status = .ready
        Log.web.info("Loaded \(webView.url?.absoluteString ?? "-", privacy: .public)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        failed(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        failed(error)
    }

    /// Links that open a new window go to the default browser.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
        }
        return nil
    }
}

private struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
