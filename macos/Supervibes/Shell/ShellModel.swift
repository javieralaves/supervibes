import Foundation
import Observation

/// The main window's state: which page shows beside the rail, and who's signed in.
@MainActor
@Observable
final class ShellModel {
    var route: Route = .web
    var isAccountMenuOpen = false
    private(set) var account: RailAccount?
    let web: WebContentModel
    /// Menus and dialogs drawn above the window's content.
    let overlays = OverlayCenter()

    @ObservationIgnored private let auth: AuthModel
    @ObservationIgnored private let client: Client

    init(auth: AuthModel) {
        self.auth = auth
        web = WebContentModel(auth: auth)
        let store = auth.store
        client = APIClient.make(baseURL: auth.baseURL, token: { store.read() })
        web.onNativePath = { [weak self] path in
            switch path {
            case "/settings": self?.openSettings()
            case "/connections": self?.open(.connections)
            default: break
            }
        }
    }

    /// The rail item to light up for what's showing.
    var activeRailItem: RailItem? {
        switch route {
        case .web: RailItem.matching(path: web.currentPath)
        case .connections: .connections
        case .settings: nil
        }
    }

    /// A rail item: its native screen, or its web page.
    func open(_ item: RailItem) {
        isAccountMenuOpen = false
        overlays.dismiss()
        if item == .connections {
            route = .connections
            return
        }
        route = .web
        // Like the web rail's links: go to the section's page unless it's already showing.
        if web.currentPath != item.href {
            web.navigate(to: item.href)
        }
    }

    func openSettings() {
        isAccountMenuOpen = false
        overlays.dismiss()
        route = .settings
    }

    func signedInChanged() async {
        guard auth.isSignedIn else {
            web.clear()
            account = nil
            route = .web
            return
        }
        web.signIn(showing: "/")
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
