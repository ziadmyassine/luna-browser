@testable import BrowserKit
import Foundation
import Testing

/// Password import and export (#5, P2.3): the CSV every other password
/// manager writes, read and written without touching the Keychain.
@Suite("Password CSV")
struct PasswordCSVTests {

    // MARK: - RFC 4180

    @Test func quotedFieldsKeepCommasNewlinesAndQuotes() {
        let text = "a,\"b,c\",\"line\nbreak\",\"say \"\"hi\"\"\"\r\nx,,z\r\n"
        #expect(PasswordCSV.records(text) == [
            ["a", "b,c", "line\nbreak", "say \"hi\""],
            ["x", "", "z"]
        ])
    }

    @Test func aByteOrderMarkAndAMissingFinalNewlineAreFine() {
        #expect(PasswordCSV.records("\u{FEFF}a,b\nc,d") == [["a", "b"], ["c", "d"]])
    }

    @Test func blankLinesAreNotRecords() {
        #expect(PasswordCSV.records("a,b\n\n\nc,d\n") == [["a", "b"], ["c", "d"]])
    }

    @Test func aTrailingEmptyFieldIsKept() {
        #expect(PasswordCSV.records("a,b,\n") == [["a", "b", ""]])
    }

    // MARK: - Each exporter's header

    @Test func chromeArcAndDia() throws {
        let csv = "name,url,username,password,note\nGitHub,https://github.com/login,ada,s3cret,work\n"
        let logins = try PasswordCSV.logins(fromCSV: csv)
        #expect(logins == [PasswordCSV.Login(
            name: "GitHub", url: "https://github.com/login", username: "ada", password: "s3cret", note: "work"
        )])
    }

    @Test func safariAndThePasswordsApp() throws {
        let csv = "Title,URL,Username,Password,Notes,OTPAuth\nexample.com (ada),https://example.com/,ada,pw,hello,\n"
        let login = try #require(try PasswordCSV.logins(fromCSV: csv).first)
        #expect(login.name == "example.com (ada)")
        #expect(login.url == "https://example.com/")
        #expect(login.username == "ada")
        #expect(login.password == "pw")
        #expect(login.note == "hello")
    }

    @Test func onePassword() throws {
        let csv = "Title,Url,Username,Password,OTPAuth,Favorite,Archived,Tags,Notes\n"
            + "Bank,bank.example,ada,pw,,false,false,,n\n"
        let login = try #require(try PasswordCSV.logins(fromCSV: csv).first)
        #expect(login.url == "bank.example")
        #expect(login.username == "ada")
        #expect(login.note == "n")
    }

    @Test func bitwardenTakesTheFirstURIAndDropsSecureNotes() throws {
        let csv = "folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp\n"
            + ",,login,Mail,,,0,\"https://mail.example/a,https://other.example\",ada,pw,\n"
            + ",,note,Diary,secret thoughts,,0,,,,\n"
        let logins = try PasswordCSV.logins(fromCSV: csv)
        #expect(logins.count == 2)
        #expect(logins[0].url == "https://mail.example/a")
        #expect(logins[0].name == "Mail")
        #expect(logins[0].password == "pw")
        #expect(logins[1].newCredential == nil, "a secure note has no site and no password")
    }

    @Test func aFileWithNoPasswordColumnIsRefused() {
        #expect(throws: PasswordCSV.Failure.unrecognisedHeader) {
            try PasswordCSV.logins(fromCSV: "Date,Amount\n2026-01-01,4\n")
        }
    }

    // MARK: - Into the store's shape

    @Test func aLoginBecomesACredentialForItsSite() throws {
        let login = PasswordCSV.Login(name: "", url: "https://accounts.example.co.uk/x", username: "ada", password: "pw", note: "")
        let credential = try #require(login.newCredential)
        #expect(credential.site == "example.co.uk")
        #expect(credential.username == "ada")
        #expect(credential.password == "pw")
        #expect(credential.originURL?.host() == "accounts.example.co.uk")
    }

    @Test func aBareHostIsReadAsHTTPS() throws {
        let login = PasswordCSV.Login(name: "", url: "github.com", username: "ada", password: "pw", note: "")
        #expect(try #require(login.newCredential).site == "github.com")
    }

    @Test func noPasswordOrNoSiteIsNothingToSave() {
        #expect(PasswordCSV.Login(name: "", url: "https://a.example", username: "u", password: "", note: "").newCredential == nil)
        #expect(PasswordCSV.Login(name: "", url: "", username: "u", password: "p", note: "").newCredential == nil)
        #expect(PasswordCSV.Login(name: "", url: "android://abc@com.app", username: "u", password: "p", note: "").newCredential == nil)
    }

    // MARK: - Export

    @Test func exportIsChromesHeaderAndReadsBack() throws {
        let logins = [
            PasswordCSV.Login(name: "a.example", url: "https://a.example/", username: "ada", password: "p,\"w\"\nx", note: ""),
            PasswordCSV.Login(name: "b.example", url: "https://b.example/", username: "", password: "pw", note: "")
        ]
        let csv = PasswordCSV.csv(logins)
        #expect(csv.hasPrefix("name,url,username,password,note\r\n"))
        #expect(try PasswordCSV.logins(fromCSV: csv) == logins)
    }
}
