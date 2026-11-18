import AppKit
import AuthenticationServices
import Foundation
import Observation

/// Loads the apps and connects or disconnects them through /api/v1. Connecting runs the app's
/// consent page in the system sign-in sheet (see src/lib/app-connect.ts).
@MainActor
@Observable
final class ConnectionsModel: NSObject {
    enum Load: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    private(set) var load: Load = .idle
    private(set) var items: [ConnectionItem] = []
    private(set) var notice: ConnectionsPage.Notice?
    private(set) var busy: ConnectionItem.Provider?

    @ObservationIgnored private let auth: AuthModel
    @ObservationIgnored private let client: Client
    @ObservationIgnored private var sheet: ASWebAuthenticationSession?

    init(auth: AuthModel) {
        self.auth = auth
        let store = auth.store
        client = APIClient.make(baseURL: auth.baseURL, token: { store.read() })
    }

    func refresh() async {
        if load != .loaded { load = .loading }
        do {
            switch try await client.listConnections() {
            case .ok(let ok):
                items = try ok.body.json.connections.map(ConnectionItem.init(api:))
                load = .loaded
            case .unauthorized:
                await auth.sessionEnded()
            case .undocumented(let status, _):
                throw AuthError.server(status)
            }
        } catch {
            Log.app.error("Connections: \(error.localizedDescription, privacy: .public)")
            if load != .loaded { load = .failed("Couldn’t load your connections. Check your connection and try again.") }
        }
    }

    // MARK: Connecting

    func connect(_ provider: ConnectionItem.Provider) {
        guard busy == nil, let apiProvider = Components.Schemas.Provider(rawValue: provider.rawValue) else { return }
        busy = provider
        notice = nil
        Task {
            do {
                switch try await client.startConnection(path: .init(provider: apiProvider)) {
                case .ok(let ok):
                    let start = try ok.body.json
                    guard let url = URL(string: start.authorizationUrl) else { return finish(error: "failed") }
                    openSheet(url: url, provider: provider, state: start.state)
                case .badRequest(let bad):
                    finish(error: (try? bad.body.json.error.code) ?? "failed")
                case .unauthorized:
                    busy = nil
                    await auth.sessionEnded()
                case .undocumented:
                    finish(error: "start_failed")
                }
            } catch {
                finish(error: "start_failed")
            }
        }
    }

    private func openSheet(url: URL, provider: ConnectionItem.Provider, state: String) {
        Log.app.info("Connecting \(provider.rawValue, privacy: .public) in the sign-in sheet")
        // @Sendable: AuthenticationServices calls this off the main thread.
        let session = ASWebAuthenticationSession(url: url, callback: .customScheme(AuthModel.callbackScheme)) {
            @Sendable [weak self] callbackURL, error in
            Task { @MainActor in
                await self?.sheetFinished(callbackURL: callbackURL, error: error, provider: provider, state: state)
            }
        }
        session.presentationContextProvider = self
        // Shares the browser's sign-ins, so a Linear or GitHub login there carries over.
        session.prefersEphemeralWebBrowserSession = false
        sheet = session
        if !session.start() { finish(error: "start_failed") }
    }

    private func sheetFinished(callbackURL: URL?, error: (any Error)?, provider: ConnectionItem.Provider, state: String) async {
        sheet = nil
        NSApp.activate()
        if let error {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return finish(error: "denied") }
            Log.app.error("Connection sheet failed: \(error.localizedDescription, privacy: .public)")
            return finish(error: "failed")
        }
        let items = callbackURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        guard value("state") == state else { return finish(error: "expired") }
        if let code = value("error") { return finish(error: code) }
        guard let code = value("code"), let apiProvider = Components.Schemas.Provider(rawValue: provider.rawValue) else {
            return finish(error: "failed")
        }

        do {
            let output = try await client.completeConnection(
                path: .init(provider: apiProvider),
                body: .json(.init(state: state, code: code))
            )
            switch output {
            case .ok(let ok):
                let item = ConnectionItem(api: try ok.body.json)
                replace(item)
                busy = nil
                notice = .connected(item.label)
                Log.app.info("Connected \(provider.rawValue, privacy: .public)")
            case .badRequest(let bad):
                finish(error: (try? bad.body.json.error.code) ?? "failed")
            case .unauthorized:
                busy = nil
                await auth.sessionEnded()
            case .undocumented:
                finish(error: "failed")
            }
        } catch {
            finish(error: "failed")
        }
    }

    private func finish(error code: String) {
        busy = nil
        notice = .failed(ConnectionItem.message(forError: code))
        Log.app.notice("Connecting ended with \(code, privacy: .public)")
    }

    // MARK: Disconnecting

    func disconnect(_ provider: ConnectionItem.Provider) {
        guard busy == nil, let apiProvider = Components.Schemas.Provider(rawValue: provider.rawValue) else { return }
        busy = provider
        notice = nil
        Task {
            defer { busy = nil }
            do {
                switch try await client.disconnect(path: .init(provider: apiProvider)) {
                case .noContent, .notFound:
                    await refresh()
                    Log.app.info("Disconnected \(provider.rawValue, privacy: .public)")
                case .unauthorized:
                    await auth.sessionEnded()
                case .undocumented:
                    notice = .failed("Couldn’t disconnect right now. Try again in a moment.")
                }
            } catch {
                notice = .failed("Couldn’t disconnect right now. Check your connection.")
            }
        }
    }

    private func replace(_ item: ConnectionItem) {
        if let index = items.firstIndex(where: { $0.provider == item.provider }) {
            items[index] = item
        }
    }
}

extension ConnectionsModel: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? NSWindow()
        }
    }
}

extension ConnectionItem {
    init(api item: Components.Schemas.Connection) {
        let state: State = switch item.connection {
        case nil: .notConnected
        case .some(let connection) where connection.status == .error: .needsAttention(message: connection.lastError)
        case .some(let connection): .connected(since: connection.connectedAt)
        }
        self.init(
            provider: Provider(rawValue: item.provider.rawValue) ?? .linear,
            label: item.label,
            description: item.description,
            configured: item.configured,
            state: state
        )
    }
}
