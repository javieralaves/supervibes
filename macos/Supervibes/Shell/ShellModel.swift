import Foundation
import Observation

/// The main window's state: which page shows beside the rail, and who's signed in.
@MainActor
@Observable
final class ShellModel {
    var route: Route = .life
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
        case .life, .goal, .area, .startSeason: .life
        case .plan: .plan
        case .calendar: .calendar
        case .connections: .connections
        case .settings: nil
        }
    }

    /// A rail item's screen.
    func open(_ item: RailItem) {
        isAccountMenuOpen = false
        overlays.dismiss()
        if item == .plan {
            planScope = .all
            planOrigin = nil
        }
        route = switch item {
        case .plan: .plan
        case .calendar: .calendar
        case .connections: .connections
        default: .life
        }
    }

    /// What to do once a goal's page opens, from a goal card's menu on the home page.
    enum GoalIntent { case updateStatus, setObjective }
    var goalIntent: GoalIntent?

    /// A goal's own page, and what to do there once it's loaded.
    func openGoal(_ id: String, then intent: GoalIntent? = nil) {
        overlays.dismiss()
        goalIntent = intent
        route = .goal(id)
    }

    /// What the planning board shows: every goal, or one.
    var planScope: BoardScope = .all
    /// The goal whose page opened the board, for its Back; nil opened from elsewhere.
    var planOrigin: String?

    /// An area's own page, from its card on Life or from a goal's page.
    func openArea(_ id: String) {
        isAccountMenuOpen = false
        overlays.dismiss()
        route = .area(id)
    }

    /// Starting a season: picks up the one being set up, or makes it.
    func openStartSeason() {
        isAccountMenuOpen = false
        overlays.dismiss()
        route = .startSeason
    }

    /// The planning board, on every goal or one, and the goal page it was opened from, if any.
    func openPlan(_ scope: BoardScope = .all, from goal: String? = nil) {
        isAccountMenuOpen = false
        overlays.dismiss()
        planScope = scope
        planOrigin = goal
        route = .plan
    }

    /// A block to select once the calendar has loaded, from clicking its notice.
    var pendingBlockId: String?
    /// Bumped to ask for the main window to open and come forward (SupervibesApp does it).
    private(set) var windowRequests = 0

    /// The calendar, on a block: what clicking a session notice opens.
    func openBlock(_ id: String) {
        isAccountMenuOpen = false
        overlays.dismiss()
        pendingBlockId = id
        route = .calendar
        windowRequests += 1
    }

    func openSettings() {
        isAccountMenuOpen = false
        overlays.dismiss()
        route = .settings
    }

    func signedInChanged() async {
        guard auth.isSignedIn else {
            account = nil
            route = .life
            return
        }
        route = .life
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
