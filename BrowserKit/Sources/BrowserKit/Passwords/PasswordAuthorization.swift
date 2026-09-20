import Foundation
import LocalAuthentication

/// Touch ID — or the login password — in front of a fill (§14.8).
///
/// Safari asks before it puts a saved password into a field, and the reason is
/// not ceremony: a saved credential is readable by whoever is sitting at an
/// unlocked Mac, and "unlocked" covers a laptop left open for two minutes.
/// The gate costs a fingerprint and removes that whole class of problem.
///
/// **It runs before the Keychain read, not after.** `PasswordCoordinator.fill`
/// asks here first and only then calls `CredentialStore.password(for:)`, so a
/// refused or cancelled prompt means the secret was never fetched into the
/// process at all — there is nothing in memory to have leaked.
///
/// `LocalAuthentication` is not AppKit, so this belongs in `BrowserKit` with
/// the rest of the decision-making rather than in `UI/` with the views
/// (§25.5, `Tools/check-no-appkit.sh`).
@MainActor
public enum PasswordAuthorization {

    /// The policy evaluation, injectable so the coordinator's rules can be
    /// tested without a fingerprint reader. Tests replace it; nothing else
    /// should.
    ///
    /// `.deviceOwnerAuthentication` rather than `.deviceOwnerAuthenticationWithBiometrics`
    /// so a Mac with no Touch ID, or a finger that will not read, falls through
    /// to the login password instead of locking the user out of their own
    /// passwords.
    public static var evaluate: @MainActor (String) async -> Bool = { reason in
        let context = LAContext()
        var error: NSError?
        // No biometrics *and* no password set. Nothing to ask, and refusing
        // here would disable autofill on that Mac entirely rather than
        // protecting anything — the machine has no lock to be behind.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            // Cancelled, or failed. Both mean "do not fill" — this is the one
            // place in the feature that fails closed.
            return false
        }
    }

    /// Whether a fill for `site` may proceed.
    ///
    /// Returns true immediately when the preference is off, so the prompt is
    /// something the user can decline once in Settings rather than dismiss on
    /// every sign-in.
    public static func confirmFill(for site: String) async -> Bool {
        guard PasswordSettings.requiresAuthentication else { return true }
        return await evaluate(String(localized: "use your saved password for \(site)"))
    }
}
