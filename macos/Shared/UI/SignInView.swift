import SwiftUI

/// The main window when nobody is signed in. Signing in happens in the system's sign-in sheet.
struct SignInView: View {
    var isSigningIn = false
    var message: String?
    var onSignIn: () -> Void = {}

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Supervibes")
                    .font(.system(size: 34, weight: .semibold))
                    .tracking(-0.8)
                Text("Sign in to see your goals, calendar and sessions.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onSignIn) {
                HStack(spacing: 8) {
                    if isSigningIn {
                        ProgressView().controlSize(.small)
                    }
                    Text(isSigningIn ? "Waiting for Google…" : "Sign in with Google")
                }
                .frame(minWidth: 200)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(isSigningIn)

            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
