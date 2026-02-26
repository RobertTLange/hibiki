import Foundation
import HibikiCLICore
import XCTest

final class DoNotDisturbPolicyTests: XCTestCase {
    private var defaultsSuitesToCleanup: [String] = []

    override func tearDown() {
        for suiteName in defaultsSuitesToCleanup {
            if let defaults = UserDefaults(suiteName: suiteName) {
                defaults.removePersistentDomain(forName: suiteName)
            }
        }
        defaultsSuitesToCleanup.removeAll()
        super.tearDown()
    }

    func testIsEnabledDefaultsToFalseWhenNoValueExists() {
        let defaults = makeDefaults()
        let sharedDefaults = makeDefaults()

        let enabled = DoNotDisturbPolicy.isEnabled(defaults: defaults, sharedDefaults: sharedDefaults)

        XCTAssertFalse(enabled)
    }

    func testIsEnabledReadsFromSharedDefaultsWhenSet() {
        let defaults = makeDefaults()
        let sharedDefaults = makeDefaults()
        sharedDefaults.set(true, forKey: DoNotDisturbPolicy.defaultsKey)

        let enabled = DoNotDisturbPolicy.isEnabled(defaults: defaults, sharedDefaults: sharedDefaults)

        XCTAssertTrue(enabled)
    }

    func testSetEnabledPersistsToBothDefaultsStores() {
        let defaults = makeDefaults()
        let sharedDefaults = makeDefaults()

        DoNotDisturbPolicy.setEnabled(true, defaults: defaults, sharedDefaults: sharedDefaults)

        XCTAssertEqual(defaults.object(forKey: DoNotDisturbPolicy.defaultsKey) as? Bool, true)
        XCTAssertEqual(sharedDefaults.object(forKey: DoNotDisturbPolicy.defaultsKey) as? Bool, true)
    }

    func testIsEnabledFallsBackToDefaultsWhenSharedStoreHasNoValue() {
        let defaults = makeDefaults()
        let sharedDefaults = makeDefaults()
        defaults.set(true, forKey: DoNotDisturbPolicy.defaultsKey)

        let enabled = DoNotDisturbPolicy.isEnabled(defaults: defaults, sharedDefaults: sharedDefaults)

        XCTAssertTrue(enabled)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "DoNotDisturbPolicyTests.\(UUID().uuidString)"
        defaultsSuitesToCleanup.append(suiteName)
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create defaults suite")
            return .standard
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
