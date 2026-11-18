import AppKit
import AuthenticationServices
import Foundation
import Observation
import WebKit

/// The app's sign-in state and session token. The server side is described in src/lib/native-auth.ts.
@MainActor
@Observable
final class AuthModel: NSObject {
    enum State: Equatable {
        case checking
        case signedOut(message: String?)
        case signingIn
        /// `email` is nil when the token couldn't be checked (for example, the server is down).
        case signedIn(email: String?)
    }

    private(set) var state: State = .checking
    let baseURL: URL

    /// Where the session token lives. Readable from any thread, for the API client.
    nonisolated let store: any TokenStore
    @ObservationIgnored private var authSession: ASWebAuthenticationSession?
    /// The state sent with the sign-in in progress; nil once its callback has been handled.
    @ObservationIgnored private var pendingState: String?
    /// No cookies, so the session only ever travels as a bearer token.
    @ObservationIgnored private let http = URLSession(configuration: .ephemeral)

    static let callbackScheme = "supervibes"

    init(baseURL: URL) {
        self.baseURL = baseURL
        self.store = TokenStores.forServer(baseURL)
        super.init()
    }

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    // MARK: Launch

    /// Checks the stored token, if any. Keeps it when the server can't be reached.
    func restore() async {
        guard let token = store.read() else {
            state = .signedOut(message: nil)
            return
        }
        do {
            if let email = try await sessionEmail(token: token) {
                state = .signedIn(email: email)
                Log.auth.info("Restored session for \(email, privacy: .private)")
            } else {
                store.delete()
                state = .signedOut(message: "Your session ended. Sign in again.")
                Log.auth.notice("Stored session is no longer valid")
            }
        } catch {
            state = .signedIn(email: nil)
            Log.auth.error("Couldn't check the session: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Signing in

    /// Opens the system sign-in sheet at /api/native/start.
    func signIn() {
        authSession?.cancel()
        let expected = Self.randomState()
        var components = URLComponents(url: baseURL.appending(path: "api/native/start"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "state", value: expected)]

        let session = ASWebAuthenticationSession(
            url: components.url!,
            callback: .customScheme(Self.callbackScheme)
        ) { @Sendable [weak self] callbackURL, error in
            // AuthenticationServices calls this on a background queue. Without @Sendable the closure
            // would inherit this class's main-actor isolation, and Swift 6 traps when it runs off main.
            Task { @MainActor in
                await self?.finishSignIn(callbackURL: callbackURL, error: error, expectedState: expected)
            }
        }
        session.presentationContextProvider = self
        // Shares the browser's Google sign-in, so it's usually one click.
        session.prefersEphemeralWebBrowserSession = false

        authSession = session
        pendingState = expected
        state = .signingIn
        Log.auth.info("Opening sign-in sheet")
        if !session.start() {
            Log.auth.error("Sign-in sheet didn't start")
            pendingState = nil
            state = .signedOut(message: "Couldn't open the sign-in window.")
        }
    }

    private func finishSignIn(callbackURL: URL?, error: (any Error)?, expectedState: String) async {
        // Only the sign-in in progress counts; a stale callback from an earlier sheet is ignored.
        guard pendingState == expectedState else { return }
        pendingState = nil
        authSession?.cancel()
        authSession = nil
        NSApp.activate()

        if let error {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                Log.auth.notice("Sign-in sheet was closed before finishing")
                state = .signedOut(message: nil)
            } else {
                Log.auth.error("Sign-in sheet failed: \(error.localizedDescription, privacy: .public)")
                state = .signedOut(message: "Sign-in didn't work. Try again.")
            }
            return
        }

        let items = callbackURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }

        guard value("state") == expectedState else {
            Log.auth.error("Sign-in callback had the wrong state; ignoring it")
            state = .signedOut(message: "Sign-in didn't work. Try again.")
            return
        }
        if let code = value("error") {
            Log.auth.notice("Sign-in returned error \(code, privacy: .public)")
            state = .signedOut(message: Self.message(forError: code))
            return
        }
        guard let oneTimeToken = value("token") else {
            Log.auth.error("Sign-in callback had neither a token nor an error")
            state = .signedOut(message: "Sign-in didn't work. Try again.")
            return
        }
        Log.auth.info("Got a one-time token; exchanging it")

        do {
            let (token, email) = try await exchange(oneTimeToken: oneTimeToken)
            try store.write(token)
            state = .signedIn(email: email)
            Log.auth.info("Signed in as \(email ?? "-", privacy: .private)")
        } catch {
            Log.auth.error("Token exchange failed: \(error.localizedDescription, privacy: .public)")
            state = .signedOut(message: "Sign-in didn't work. Try again.")
        }
    }

    // MARK: Signing out

    /// Ends this app's session on the server, then forgets it here (including the web view's cookie).
    func signOut(message: String? = nil) async {
        if let token = store.read() {
            var request = URLRequest(url: baseURL.appending(path: "api/auth/sign-out"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{}".utf8)
            _ = try? await http.data(for: request)
        }
        store.delete()
        await WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )
        state = .signedOut(message: message)
        Log.auth.info("Signed out")
    }

    /// The web app sent the web view to /sign-in: the session is gone on the server.
    func sessionEnded() async {
        guard isSignedIn else { return }
        await signOut(message: "Your session ended. Sign in again.")
    }

    // MARK: Web view handoff

    /// A URL that signs the web view in with this app's session, then continues to `next`.
    func handoffURL(next: String = "/") async throws -> URL {
        guard let token = store.read() else { throw AuthError.notSignedIn }
        var request = URLRequest(url: baseURL.appending(path: "api/auth/one-time-token/generate"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await http.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw AuthError.sessionEnded }
        guard status == 200 else { throw AuthError.server(status) }
        let oneTimeToken = try JSONDecoder().decode(OneTimeToken.self, from: data).token

        var components = URLComponents(url: baseURL.appending(path: "api/native/handoff"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "token", value: oneTimeToken), URLQueryItem(name: "next", value: next)]
        return components.url!
    }

    // MARK: Server calls

    /// Trades the one-time token from the sign-in sheet for this app's session token.
    private func exchange(oneTimeToken: String) async throws -> (token: String, email: String?) {
        var request = URLRequest(url: baseURL.appending(path: "api/auth/one-time-token/verify"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OneTimeToken(token: oneTimeToken))
        let (data, response) = try await http.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let token = http.value(forHTTPHeaderField: "set-auth-token"), !token.isEmpty else {
            throw AuthError.server((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let email = (try? JSONDecoder().decode(SessionPayload.self, from: data))?.user.email
        return (token, email)
    }

    /// The signed-in email for `token`, or nil if the server says the session is gone.
    private func sessionEmail(token: String) async throws -> String? {
        var request = URLRequest(url: baseURL.appending(path: "api/auth/get-session"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await http.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AuthError.server((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        // better-auth answers `null` when there's no session.
        return (try? JSONDecoder().decode(SessionPayload.self, from: data))?.user.email
    }

    // MARK: Helpers

    private static func randomState() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func message(forError code: String) -> String {
        switch code {
        case "access_denied": "Sign-in was cancelled in Google."
        case "not_signed_in": "Google didn't finish signing you in. Try again."
        case "forbidden", "unable_to_create_user", "signup_disabled": "This Google account isn't on the access list."
        default: "Sign-in didn't work. Try again."
        }
    }
}

extension AuthModel: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? NSWindow()
        }
    }
}

enum AuthError: LocalizedError {
    case notSignedIn
    case sessionEnded
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Not signed in."
        case .sessionEnded: "The session ended."
        case .server(let status): "The server answered \(status)."
        }
    }
}

private struct OneTimeToken: Codable {
    let token: String
}

private struct SessionPayload: Decodable {
    struct User: Decodable { let email: String }
    let user: User
}
