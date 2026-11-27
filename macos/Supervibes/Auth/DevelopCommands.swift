#if DEBUG
import SwiftUI

/// Debug builds only: a Develop menu for trying the app as someone new. Starting as someone new
/// signs out and makes a fresh throwaway person on the local server (see AuthModel.startAsNewPerson),
/// so first run can be gone through again from the start; Replay First Run goes through it again as
/// whoever is signed in. To be yourself again, sign out and sign in
/// with Google as usual.
struct DevelopCommands: Commands {
    let auth: AuthModel
    let firstRun: FirstRunModel

    var body: some Commands {
        CommandMenu("Develop") {
            Button("Start as Someone New") {
                Task { await auth.startAsNewPerson() }
            }
            .keyboardShortcut("n", modifiers: [.command, .option, .shift])
            Button("Replay First Run") { firstRun.replay() }
                .disabled(!auth.isSignedIn)
            Divider()
            Text(auth.signedInEmail.map { "Signed in as \($0)" } ?? "Not signed in")
        }
    }
}
#endif
