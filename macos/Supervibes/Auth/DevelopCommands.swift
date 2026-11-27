#if DEBUG
import SwiftUI

/// Debug builds only: a Develop menu for trying the app as someone new. Starting as someone new
/// signs out and makes a fresh throwaway person on the local server (see AuthModel.startAsNewPerson),
/// so first run can be gone through again from the start. To be yourself again, sign out and sign in
/// with Google as usual.
struct DevelopCommands: Commands {
    let auth: AuthModel

    var body: some Commands {
        CommandMenu("Develop") {
            Button("Start as Someone New") {
                Task { await auth.startAsNewPerson() }
            }
            .keyboardShortcut("n", modifiers: [.command, .option, .shift])
            Divider()
            Text(auth.signedInEmail.map { "Signed in as \($0)" } ?? "Not signed in")
        }
    }
}
#endif
