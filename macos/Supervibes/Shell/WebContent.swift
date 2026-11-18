import AppKit
import SwiftUI
import WebKit

/// The web pages in the app's window: the Supervibes web app in a WKWebView, signed in with the
/// app's own session, drawn without its own rail and frame (the app draws those natively).
struct WebContentView: View {
    let model: WebContentModel

    var body: some View {
        WebViewHost(webView: model.webView)
            .overlay {
                if case .unreachable(let reason) = model.status {
                    ContentUnavailableView {
                        Label("Can't reach Supervibes", systemImage: "network.slash")
                    } description: {
                        Text("Nothing answered at \(model.baseURL.absoluteString). \(reason)")
                    } actions: {
                        Button("Try Again") { model.reload() }
                            .keyboardShortcut(.defaultAction)
                    }
                    .background(Theme.background)
                }
            }
    }
}

@MainActor
@Observable
final class WebContentModel: NSObject {
    enum Status: Equatable {
        case idle
        case loading
        case ready
        case unreachable(String)
    }

    private(set) var status: Status = .idle
    /// The web page showing, e.g. "/calendar"; nil until one has loaded.
    private(set) var currentPath: String?

    /// Called with a web path that has a native screen now, when the page tries to go there.
    @ObservationIgnored var onNativePath: (String) -> Void = { _ in }

    /// Web pages that have a native screen. Links to them open that instead.
    static let nativePaths: Set<String> = ["/settings", "/connections"]

    @ObservationIgnored private let auth: AuthModel
    @ObservationIgnored private var urlObservation: NSKeyValueObservation?
    @ObservationIgnored private var pendingPath = "/"

    var baseURL: URL { auth.baseURL }

    @ObservationIgnored
    lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let scripts = configuration.userContentController
        // Tell the page it's inside the Mac app before it draws, so it drops its rail and frame.
        scripts.addUserScript(WKUserScript(
            source: #"document.documentElement.dataset.shell = "mac";"#,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        // Next.js links navigate inside the page (no WKNavigation), so links to native screens are
        // caught in the page before React sees them, and passed here.
        scripts.addUserScript(WKUserScript(
            source: Self.nativeLinksScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        scripts.add(NativeLinkHandler(model: self), name: "nativeLink")

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        view.underPageBackgroundColor = .clear
        #if DEBUG
        // Lets Safari's Web Inspector attach (Develop menu → this Mac → Supervibes).
        view.isInspectable = true
        #endif
        // In-page navigations change the URL without a load; follow them for the rail.
        urlObservation = view.observe(\.url, options: [.new]) { [weak self] _, change in
            let url = change.newValue ?? nil
            let path = url?.scheme == "about" ? nil : url?.path()
            Task { @MainActor in self?.currentPath = path }
        }
        return view
    }()

    init(auth: AuthModel) {
        self.auth = auth
        super.init()
    }

    /// Signs the web view in with the app's session (a one-time handoff), then shows `path`.
    func signIn(showing path: String = "/") {
        pendingPath = path
        status = .loading
        Task {
            do {
                let url = try await auth.handoffURL(next: path)
                Log.web.info("Handing the session to the web view, then loading \(path, privacy: .public)")
                webView.load(URLRequest(url: url))
            } catch AuthError.sessionEnded {
                await auth.sessionEnded()
            } catch {
                failed(error)
            }
        }
    }

    /// Shows a web page, moving within the page like a link would when it can.
    func navigate(to path: String) {
        guard status == .ready else { return signIn(showing: path) }
        let script = """
        (() => {
          const router = window.next && window.next.router;
          if (router && typeof router.push === "function") { router.push(\(Self.jsString(path))); return true; }
          return false;
        })()
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard (result as? Bool) != true else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.webView.load(URLRequest(url: self.baseURL.appending(path: path)))
            }
        }
    }

    func reload() {
        signIn(showing: currentPath ?? pendingPath)
    }

    func clear() {
        status = .idle
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    private static func jsString(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [value])
        let array = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"/\"]"
        return String(array.dropFirst().dropLast())
    }

    private static var nativeLinksScript: String {
        let paths = nativePaths.map { "\"\($0)\"" }.joined(separator: ",")
        return """
        (() => {
          const native = new Set([\(paths)]);
          document.addEventListener("click", (event) => {
            if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
            const link = event.target instanceof Element ? event.target.closest("a[href]") : null;
            if (!link) return;
            const url = new URL(link.href, location.href);
            if (url.origin !== location.origin || !native.has(url.pathname)) return;
            event.preventDefault();
            event.stopImmediatePropagation();
            window.webkit.messageHandlers.nativeLink.postMessage(url.pathname);
          }, true);
        })();
        """
    }

    fileprivate func openNative(path: String) {
        guard Self.nativePaths.contains(path) else { return }
        Log.web.info("Opening native screen for \(path, privacy: .public)")
        onNativePath(path)
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

extension WebContentModel: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .allow }

        // The web app only goes to its sign-in page when the session is gone. Sign in natively instead.
        if isOurs(url), url.path() == "/sign-in" {
            Log.web.notice("Web app asked to sign in; switching to native sign-in")
            await auth.sessionEnded()
            return .cancel
        }
        // A full page load of a screen that's native now (typed URL, reload): open it natively.
        if isOurs(url), Self.nativePaths.contains(url.path()), navigationAction.targetFrame?.isMainFrame == true {
            openNative(path: url.path())
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

/// Receives `nativeLink` messages from the page. Holds the model weakly: WebKit keeps message handlers alive.
private final class NativeLinkHandler: NSObject, WKScriptMessageHandler {
    weak var model: WebContentModel?

    init(model: WebContentModel) {
        self.model = model
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let path = message.body as? String else { return }
        MainActor.assumeIsolated { model?.openNative(path: path) }
    }
}

private struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
