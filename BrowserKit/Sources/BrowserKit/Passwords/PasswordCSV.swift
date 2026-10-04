import Foundation

/// The CSV other password managers import and export (#5, P2.3): Chrome, Arc
/// and Dia write `name,url,username,password,note`, Safari and the Passwords
/// app `Title,URL,Username,Password,Notes,OTPAuth`, 1Password `Title,Url,…`,
/// Bitwarden `…,name,notes,…,login_uri,login_username,login_password,…`.
/// Columns are found by header name, so their order and extras do not matter.
///
/// Pure text in and out, so it is tested without the Keychain;
/// `CredentialStore` does the storing.
public enum PasswordCSV {

    /// One row of a password export. Carries a password, so like
    /// `NewCredential` it is not `Codable` or `CustomStringConvertible`.
    public struct Login: Equatable, Sendable {
        public var name: String
        public var url: String
        public var username: String
        public var password: String
        public var note: String

        public init(name: String, url: String, username: String, password: String, note: String) {
            self.name = name
            self.url = url
            self.username = username
            self.password = password
            self.note = note
        }

        /// What `CredentialStore.save` takes, or nil when the row has no
        /// password or no web site to own it: a Bitwarden secure note, an
        /// `android://` app login, an IP-less blank.
        public var newCredential: NewCredential? {
            guard !password.isEmpty else { return nil }
            let trimmed = url.trimmingCharacters(in: .whitespaces)
            // 1Password and Bitwarden keep whatever the user typed, which is
            // often a bare host.
            let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
            guard let origin = URL(string: candidate),
                  ["http", "https"].contains(origin.scheme?.lowercased()),
                  let site = PublicSuffix.siteKey(forHost: origin.host())
            else { return nil }
            return NewCredential(site: site, username: username, password: password, originURL: origin)
        }
    }

    public enum Failure: Error, Equatable {
        /// No URL or no password column: not a password export.
        case unrecognisedHeader
    }

    // MARK: - Reading

    /// Header names, lowercased, each exporter uses for a field.
    /// Computed because key paths are not `Sendable`, so a stored table
    /// would be shared mutable state to Swift 6.
    private static var aliases: [WritableKeyPath<Login, String>: Set<String>] {
        [
            \.name: ["name", "title"],
            \.url: ["url", "login_uri", "website", "web site", "login url"],
            \.username: ["username", "login_username", "user name", "login name"],
            \.password: ["password", "login_password"],
            \.note: ["note", "notes"]
        ]
    }

    public static func logins(fromCSV text: String) throws -> [Login] {
        var rows = records(text)
        guard !rows.isEmpty else { throw Failure.unrecognisedHeader }
        let header = rows.removeFirst().map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        var columns: [WritableKeyPath<Login, String>: Int] = [:]
        for (path, names) in aliases {
            columns[path] = header.firstIndex(where: names.contains)
        }
        guard columns[\.url] != nil, columns[\.password] != nil else { throw Failure.unrecognisedHeader }

        return rows.map { row in
            var login = Login(name: "", url: "", username: "", password: "", note: "")
            for (path, index) in columns where index < row.count {
                login[keyPath: path] = row[index]
            }
            // Bitwarden joins several URIs for one login with commas.
            login.url = String(login.url.split(separator: ",").first ?? "")
            return login
        }
    }

    /// RFC 4180 records: quoted fields may hold commas, line breaks and `""`
    /// for a quote; lines end in CRLF or LF; a leading BOM is dropped; blank
    /// lines are skipped.
    ///
    /// Walks unicode scalars, not `Character`s: Swift reads CRLF as one
    /// grapheme, which would hide the CR from the end-of-line check.
    public static func records(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = String.UnicodeScalarView()
        var quoted = false
        var scalars = text.unicodeScalars[...]
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }

        func endRecord() {
            record.append(String(field))
            field = String.UnicodeScalarView()
            if record != [""] { records.append(record) }
            record = []
        }

        while let scalar = scalars.popFirst() {
            if quoted {
                quoted = readQuoted(scalar, rest: &scalars, into: &field)
                continue
            }
            switch scalar {
            case "\"": quoted = true
            case ",":
                record.append(String(field))
                field = String.UnicodeScalarView()
            case "\r":
                if scalars.first == "\n" { scalars.removeFirst() }
                endRecord()
            case "\n": endRecord()
            default: field.append(scalar)
            }
        }
        if !field.isEmpty || !record.isEmpty { endRecord() }
        return records
    }

    /// One scalar inside quotes. Returns whether the field is still quoted:
    /// `""` is a literal quote, a lone `"` closes the field.
    private static func readQuoted(
        _ scalar: Unicode.Scalar,
        rest: inout Substring.UnicodeScalarView,
        into field: inout String.UnicodeScalarView
    ) -> Bool {
        guard scalar == "\"" else { field.append(scalar); return true }
        guard rest.first == "\"" else { return false }
        rest.removeFirst()
        field.append(scalar)
        return true
    }

    // MARK: - Writing

    /// Chrome's layout, because every importer listed above reads it.
    public static func csv(_ logins: [Login]) -> String {
        let rows = [["name", "url", "username", "password", "note"]]
            + logins.map { [$0.name, $0.url, $0.username, $0.password, $0.note] }
        return rows.map { $0.map(escape).joined(separator: ",") + "\r\n" }.joined()
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { ",\"\r\n".contains($0) }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
