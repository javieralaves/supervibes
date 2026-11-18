import Foundation

/// An app Supervibes can read activity from, and whether it's connected.
struct ConnectionItem: Identifiable, Hashable, Sendable {
    enum Provider: String, CaseIterable, Hashable, Sendable {
        case linear, github, granola
    }

    enum State: Hashable, Sendable {
        case notConnected
        case connected(since: Date)
        /// Connected, but the last read failed; `message` says why.
        case needsAttention(message: String?)
    }

    var id: Provider { provider }
    let provider: Provider
    let label: String
    let description: String
    /// false until the server has this app's credentials ("Needs one-time setup").
    let configured: Bool
    let state: State

    var isConnected: Bool { state != .notConnected }
}

extension ConnectionItem {
    /// What the web's status banner says for a result code (src/app/(app)/connections/status-banner.tsx).
    static func message(forError code: String) -> String {
        switch code {
        case "denied": "You cancelled the connection. Nothing was changed."
        case "expired": "That sign-in took too long or came from another session. Try connecting again."
        case "start_failed": "Couldn’t reach that app’s sign-in. Try again in a moment."
        case "not_configured": "This app needs a one-time setup before it can connect."
        default: "The app didn’t finish connecting. Try again in a moment."
        }
    }
}
