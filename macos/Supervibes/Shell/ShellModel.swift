import Foundation
import Observation

/// The main window's state: which page shows beside the rail, and who's signed in.
@MainActor
@Observable
final class ShellModel {
    var route: Route = .goals
    var isAccountMenuOpen = false
    private(set) var account: RailAccount?
    /// Menus and dialogs drawn above the window's content.
    let overlays = OverlayCenter()

    @ObservationIgnored private let auth: AuthModel
    @ObservationIgnored private let client: Client

    init(auth: AuthModel) {
        self.auth = auth
        let store = auth.store
        client = APIClient.make(baseURL: auth.baseURL, token: { store.read() })
    }

    /// The rail item to light up for what's showing.
    var activeRailItem: RailItem? {
        switch route {
        case .goals, .goal: .goals
        case .calendar: .calendar
        case .connections: .connections
        case .settings: nil
        }
    }

    /// A rail item's screen.
    func open(_ item: RailItem) {
        isAccountMenuOpen = false
        overlays.dismiss()
        route = switch item {
        case .calendar: .calendar
        case .connections: .connections
        default: .goals
        }
    }

    /// A goal's own page.
    func openGoal(_ id: String) {
        overlays.dismiss()
        route = .goal(id)
    }

    func openSettings() {
        isAccountMenuOpen = false
        overlays.dismiss()
        route = .settings
    }

    func signedInChanged() async {
        guard auth.isSignedIn else {
            account = nil
            route = .goals
            return
        }
        route = .goals
        await loadAccount()
    }

    private func loadAccount() async {
        do {
            if case .ok(let ok) = try await client.getMe() {
                let me = try ok.body.json
                account = RailAccount(
                    name: me.user.name,
                    email: me.user.email,
                    imageURL: me.user.image.flatMap(URL.init(string:))
                )
            }
        } catch {
            Log.app.error("Account: \(error.localizedDescription, privacy: .public)")
        }
    }
}
