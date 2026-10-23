//
//  TestHostDefaultsTests.swift
//  LunaTests
//
//  The unit-test host is the real app, so its defaults domain is the user's
//  own. A setting they changed must not reach a test, and a setting a test
//  changes must not reach their Luna.
//

import Foundation
import XCTest
@testable import Luna

final class TestHostDefaultsTests: XCTestCase {

    /// A key no build of Luna reads, removed again from both sides whatever
    /// the outcome, so the user's domain is left as it was found.
    private let probe = "luna.tests.defaultsIsolationProbe" as CFString
    private let appDomain = (Bundle.main.bundleIdentifier ?? "dev.novapps.luna") as CFString

    override func tearDown() {
        CFPreferencesSetAppValue(probe, nil, appDomain)
        CFPreferencesAppSynchronize(appDomain)
        UserDefaults.standard.removeObject(forKey: probe as String)
        super.tearDown()
    }

    func testTheAppsOwnDomainIsNotVisibleToTests() {
        CFPreferencesSetAppValue(probe, "set in Luna" as CFString, appDomain)
        CFPreferencesAppSynchronize(appDomain)

        XCTAssertNil(UserDefaults.standard.object(forKey: probe as String))
    }

    func testWhatATestWritesDoesNotReachTheAppsOwnDomain() {
        UserDefaults.standard.set("set by a test", forKey: probe as String)

        XCTAssertNil(CFPreferencesCopyAppValue(probe, appDomain))
    }
}
