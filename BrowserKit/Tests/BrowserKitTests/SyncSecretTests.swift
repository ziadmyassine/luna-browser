@testable import BrowserKit
import Foundation
import Testing

/// The per-account secret and the site record names keyed by it (docs/SYNC-PLAN.md §1, S5).
@Suite("Sync secret and site record names (§31.2)")
struct SyncSecretTests {

    private let secret = SyncSecret(bytes: Data(repeating: 7, count: 32))

    @Test func theSameSecretAndHostGiveTheSameName() {
        let again = SyncSecret(bytes: Data(repeating: 7, count: 32))
        #expect(secret.siteRecordName(forHost: "example.com") == again.siteRecordName(forHost: "example.com"))
        #expect(secret.siteRecordName(forHost: "example.com") != secret.siteRecordName(forHost: "example.org"))
    }

    /// Pinned against Python's `hmac` and `base64.b32encode`. Every Mac on the account has
    /// to derive the same name forever; a change here orphans every site record.
    @Test func theNameMatchesAnIndependentHMACAndBase32() {
        #expect(secret.siteRecordName(forHost: "example.com") == "site-yeyikoc2pz774jbsweobmn36ws")
    }

    @Test func aDifferentSecretGivesADifferentName() {
        let other = SyncSecret(bytes: Data(repeating: 8, count: 32))
        #expect(secret.siteRecordName(forHost: "example.com") != other.siteRecordName(forHost: "example.com"))
    }

    @Test func theNameNeverContainsTheHost() {
        for host in ["example.com", "a.b", "mail.google.com"] {
            let name = secret.siteRecordName(forHost: host)
            #expect(!name.contains(host))
            #expect(name.hasPrefix("site-"))
            #expect(name.count == "site-".count + 26)
            #expect(name.dropFirst(5).allSatisfy { "abcdefghijklmnopqrstuvwxyz234567".contains($0) })
        }
        #expect(!secret.siteRecordName(forHost: "example.com").contains("example"))
    }

    @Test func aGeneratedSecretIs32RandomBytes() {
        let first = SyncSecret.generate()
        #expect(first.bytes.count == 32)
        #expect(first != SyncSecret.generate())
    }

    @Test func theSecretTravelsEncryptedInTheMetaZone() throws {
        let record = secret.record(stored: nil)

        #expect(record.recordType == "SyncSecret")
        #expect(record.recordName == "secret")
        #expect(record.zone == SyncZone.meta.rawValue)
        #expect(record.fields["secret"] == SyncField(.bytes(secret.bytes), encrypted: true))
        #expect(SyncSecret(record: record) == secret)
        var short = record
        short.fields["secret"] = SyncField(.bytes(Data([1])), encrypted: true)
        #expect(SyncSecret(record: short) == nil, "a secret that is not 32 bytes is not one")
    }

    @Test func nothingKeyedIsNamedBeforeTheSecretIsSettled() {
        var state = SyncSecretState()
        #expect(state.siteRecordName(forHost: "example.com") == nil)

        let proposal = state.proposal()
        #expect(state.proposal() == proposal, "one proposal until it settles")
        #expect(state.siteRecordName(forHost: "example.com") == nil, "a proposal the server has not accepted keys nothing")

        state.saved()
        #expect(state.siteRecordName(forHost: "example.com") == proposal.siteRecordName(forHost: "example.com"))
    }

    @Test func aFetchedSecretSettlesWithoutAProposal() {
        var state = SyncSecretState()
        state.received(secret.record(stored: nil))
        #expect(state.settled == secret)
    }

    /// Two Macs turn sync on at once. Both propose; the second save fails with
    /// `serverRecordChanged`, and the record in that error is the first Mac's.
    @Test func aRaceResolvesToTheServersSecret() {
        var state = SyncSecretState()
        let mine = state.proposal()
        let theirs = SyncSecret.generate()

        state.received(theirs.record(stored: nil))
        state.saved()

        #expect(state.settled == theirs)
        #expect(state.siteRecordName(forHost: "example.com") == theirs.siteRecordName(forHost: "example.com"))
        #expect(state.siteRecordName(forHost: "example.com") != mine.siteRecordName(forHost: "example.com"))
    }
}
