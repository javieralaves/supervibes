import AppKit
import SwiftUI
import WebKit

/// The main window's content while screens are still web: the Supervibes web app in a WKWebView,
/// signed in with the app's own session, plus native screens for signing in and for when the
/// server can't be reached.
struct WebShellView: View {
    let auth: AuthModel
    @State private var model: WebShellModel

    init(auth: AuthModel) {
        self.auth = auth
        _model = State(initialValue: WebShellModel(auth: auth))
    }

    var body: some View {
        WebViewHost(webView: model.webView)
            .overlay {
                switch auth.state {
                case .checking:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.background)
                case .signedOut(let message):
                    SignInView(message: message, onSignIn: auth.signIn)
                case .signingIn:
                    SignInView(isSigningIn: true)
                case .signedIn:
                    if case .unreachable(let reason) = model.status {
                        ContentUnavailableView {
                            Label("Can't reach Supervibes", systemImage: "network.slash")
                        } description: {
                            Text("Nothing answered at \(auth.baseURL.absoluteString). \(reason)")
                        } actions: {
                            Button("Try Again") { model.load() }
                                .keyboardShortcut(.defaultAction)
                        }
                        .background(.background)
                    }
                }
            }
            .task(id: auth.isSignedIn) {
                if auth.isSignedIn {
                    model.load()
                } else {
                    model.clear()
                }
            }
    }
}

@MainActor
@Observable
final class WebShellModel: NSObject {
    enum Status: Equatable {
        case idle
        case loading
        case ready
        case unreachable(String)
    }

    private(set) var status: Status = .idle
    @ObservationIgnored private let auth: AuthModel

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

    init(auth: AuthModel) {
        self.auth = auth
        super.init()
    }

    /// Signs the web view in with the app's session (a one-time handoff), then shows the web app.
    func load(next: String = "/") {
        status = .loading
        Task {
            do {
                let url = try await auth.handoffURL(next: next)
                Log.web.info("Handing the session to the web view, then loading \(next, privacy: .public)")
                webView.load(URLRequest(url: url))
            } catch AuthError.sessionEnded {
                await auth.sessionEnded()
            } catch {
                failed(error)
            }
        }
    }

    func clear() {
        status = .idle
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    fileprivate func failed(_ error: any Error) {
        let error = error as NSError
        // Cancelled loads (including ones we cancel on purpose) aren't failures.
        if error.code == NSURLErrorCancelled || (error.domain == "WebKitErrorDomain" && error.code == 102) {
            return
        }
        Log.web.error("Load failed: \(error.localizedDescription, privacy: .public)")
        let hint = auth.baseURL.host() == "localhost" ? "Start it with `npm run dev`, then try again." : error.localizedDescription
        status = .unreachable(hint)
    }

    private func isOurs(_ url: URL?) -> Bool {
        url?.host() == auth.baseURL.host() && url?.port == auth.baseURL.port
    }
}

extension WebShellModel: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .allow }

        // The web app only goes to its sign-in page when the session is gone. Sign in natively instead.
        if isOurs(url), url.path() == "/sign-in" {
            Log.web.notice("Web app asked to sign in; switching to native sign-in")
            await auth.sessionEnded()
            return .cancel
        }
        // Google won't sign in inside an embedded web view.
        if url.host() == "accounts.google.com" {
            Log.web.notice("Stopped Google sign-in in the web view")
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView.url?.scheme != "about" else { return }
        status = .ready
        Log.web.info("Loaded \(webView.url?.path() ?? "-", privacy: .public)")
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
