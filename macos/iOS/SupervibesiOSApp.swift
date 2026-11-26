import SwiftUI

/// Spike: Supervibes on iPhone. Signs in through the same system sheet as the Mac app and shows
/// today in the shared DayView, against the same /api/v1.
@main
struct SupervibesiOSApp: App {
    @State private var auth: AuthModel

    init() {
        Log.app.info("Launched on iOS, talking to \(AppConfig.baseURL.absoluteString, privacy: .public)")
        _auth = State(initialValue: AuthModel(baseURL: AppConfig.baseURL))
    }

    var body: some Scene {
        WindowGroup {
            PhoneRoot(auth: auth)
                .task { await auth.restore() }
        }
    }
}
