import SwiftUI

/// Sign-in while signed out; otherwise today's calendar.
struct PhoneRoot: View {
    let auth: AuthModel
    @State private var overlays = OverlayCenter()

    var body: some View {
        Group {
            switch auth.state {
            case .checking:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut(let message):
                SignInView(message: message, onSignIn: auth.signIn).padding(24)
            case .signingIn:
                SignInView(isSigningIn: true).padding(24)
            case .signedIn(let email):
                NavigationStack {
                    TodayScreen(auth: auth)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Menu {
                                    if let email { Text(email) }
                                    Button("Sign Out", role: .destructive) {
                                        Task { await auth.signOut() }
                                    }
                                } label: {
                                    Image(systemName: "person.crop.circle")
                                }
                            }
                        }
                        .toolbarTitleDisplayMode(.inline)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .overlayHost(overlays)
    }
}
