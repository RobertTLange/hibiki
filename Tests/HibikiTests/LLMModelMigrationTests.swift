import XCTest
import HibikiShared

final class LLMModelMigrationTests: XCTestCase {
    func testDefaultModelIsGPT6Luna() {
        XCTAssertEqual(LLMModel.defaultModel, .gpt6Luna)
    }

    func testLegacyDefaultMigratesToCurrentDefault() {
        XCTAssertEqual(LLMModelMigration.migratedValue(for: "gpt-5-nano"), "gpt-6-luna")
    }

    func testExplicitNonLegacyChoicesAreKept() {
        for stored in ["gpt-5-mini", "gpt-5.2", "gpt-6-luna", "custom-model"] {
            XCTAssertEqual(LLMModelMigration.migratedValue(for: stored), stored)
        }
    }
}
