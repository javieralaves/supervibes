#if DEBUG
import SwiftUI

/// Debug builds only: a Develop menu for trying the app as someone new, and going back to yourself.
/// Starting as someone new makes a fresh throwaway person on the local server and keeps your own
/// session aside (see AuthModel.startAsNewPerson), so first run can be gone through from the start;
/// Switch to yourself picks your session back up. Replay First Run goes through it again as whoever
/// is signed in.
struct DevelopCommands: Commands {
    let auth: AuthModel
    let firstRun: FirstRunModel

    var body: some Commands {
        CommandMenu("Develop") {
            // Back to your own account (on whichever database local development uses), from a test person.
            if AuthModel.isTestPerson(auth.signedInEmail) || !auth.isSignedIn {
                Button(auth.personalEmail.map { "Switch to \($0)" } ?? "Sign In as Yourself…") {
                    Task { await auth.switchToPersonal() }
                }
                .keyboardShortcut("y", modifiers: [.command, .option, .shift])
            }
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
