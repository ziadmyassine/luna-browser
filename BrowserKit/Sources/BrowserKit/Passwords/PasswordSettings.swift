import Foundation

/// The three switches §14 actually has, in the same `UserDefaults` shape
/// `WebViewFactory.Key` uses for §3.9's.
///
/// Three and not ten: every one of these turns off something the user can
/// otherwise see happening. A preference for something invisible is a
/// preference nobody can check, and §30.4's rule about dead switches applies to
/// settings that do nothing as much as to ones that are greyed out.
public enum PasswordSettings {

    public enum Key {
        public static let enabled = "passwords.enabled"
        public static let offerToSave = "passwords.offerToSave"
        public static let generate = "passwords.generate"
        public static let requireAuthentication = "passwords.requireAuthentication"
    }

    /// The master switch. Off means the detection script is not injected at
    /// all — not injected-but-ignored, so a user who turns this off pays
    /// nothing on every page load for a feature they declined.
    public static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Key.enabled) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.enabled) }
    }

    /// §14.4's chip.
    public static var offersToSave: Bool {
        get { UserDefaults.standard.object(forKey: Key.offerToSave) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.offerToSave) }
    }

    /// §14.5's suggestion on signup forms.
    public static var offersGeneratedPasswords: Bool {
        get { UserDefaults.standard.object(forKey: Key.generate) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.generate) }
    }

    /// Touch ID, or the login password, in front of every fill.
    ///
    /// On by default, which is the one place §14 chooses friction. Safari
    /// does the same, and a saved password is otherwise readable by anyone who
    /// reaches an unlocked Mac — a bar low enough that leaving it to the user
    /// to discover would be the wrong default. It is a switch, not a law: a
    /// user who finds it tedious can turn it off in Settings.
    public static var requiresAuthentication: Bool {
        get { UserDefaults.standard.object(forKey: Key.requireAuthentication) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.requireAuthentication) }
    }
}
