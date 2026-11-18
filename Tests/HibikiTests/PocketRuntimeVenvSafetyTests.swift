import XCTest
@testable import HibikiPocketRuntime

final class PocketRuntimeVenvSafetyTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("hibiki-venv-safety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    func testMissingPathIsReplaceable() {
        let missing = scratch.appendingPathComponent("does-not-exist", isDirectory: true)
        XCTAssertTrue(PocketTTSRuntimeManager.isReplaceableVenvDirectory(missing))
    }

    func testEmptyDirectoryIsReplaceable() {
        XCTAssertTrue(PocketTTSRuntimeManager.isReplaceableVenvDirectory(scratch))
    }

    func testExistingVirtualenvIsReplaceable() throws {
        try Data().write(to: scratch.appendingPathComponent("pyvenv.cfg"))
        try Data().write(to: scratch.appendingPathComponent("other"))
        XCTAssertTrue(PocketTTSRuntimeManager.isReplaceableVenvDirectory(scratch))
    }

    func testDirectoryWithUnrelatedContentIsNotReplaceable() throws {
        try Data("keep me".utf8).write(to: scratch.appendingPathComponent("notes.txt"))
        XCTAssertFalse(PocketTTSRuntimeManager.isReplaceableVenvDirectory(scratch))
    }

    func testRegularFileIsNotReplaceable() throws {
        let file = scratch.appendingPathComponent("file")
        try Data().write(to: file)
        XCTAssertFalse(PocketTTSRuntimeManager.isReplaceableVenvDirectory(file))
    }

    func testHomeDirectoryIsNotReplaceable() {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        XCTAssertFalse(PocketTTSRuntimeManager.isReplaceableVenvDirectory(home))
    }

    /// Regression: a managed venv path pointing at a normal directory used to be deleted recursively.
    @MainActor
    func testReinstallRefusesToDeleteNonVenvDirectory() async throws {
        let keep = scratch.appendingPathComponent("notes.txt")
        try Data("keep me".utf8).write(to: keep)

        do {
            try await PocketTTSRuntimeManager.shared.reinstall(venvPath: scratch.path)
            XCTFail("reinstall should refuse a non-venv directory")
        } catch PocketRuntimeError.unsafeVenvPath(let path) {
            XCTAssertEqual(
                URL(fileURLWithPath: path).standardizedFileURL.path,
                scratch.standardizedFileURL.path
            )
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: keep.path))
    }
}
