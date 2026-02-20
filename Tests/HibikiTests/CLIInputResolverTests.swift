import Foundation
import HibikiCLICore
import XCTest

final class CLIInputResolverTests: XCTestCase {
    func testResolveReturnsTextWhenOnlyTextProvided() throws {
        let resolved = try CLIInputResolver.resolve(text: "Hello world", fileName: nil)
        XCTAssertEqual(resolved, "Hello world")
    }

    func testResolveThrowsWhenBothInputsProvided() {
        XCTAssertThrowsError(try CLIInputResolver.resolve(text: "Hello", fileName: "README.md")) { error in
            XCTAssertEqual(error as? CLIInputError, .conflictingInputs)
        }
    }

    func testResolveThrowsWhenNoInputsProvided() {
        XCTAssertThrowsError(try CLIInputResolver.resolve(text: nil, fileName: nil)) { error in
            XCTAssertEqual(error as? CLIInputError, .missingInput)
        }
    }

    func testResolveThrowsWhenFileDoesNotExist() {
        XCTAssertThrowsError(try CLIInputResolver.resolve(text: nil, fileName: "does-not-exist.txt")) { error in
            XCTAssertEqual(error as? CLIInputError, .fileNotFound("does-not-exist.txt"))
        }
    }

    func testResolveThrowsWhenFileIsNonUTF8() throws {
        let fileURL = try createTemporaryFile(data: Data([0xFF, 0xFE, 0x00]))
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        XCTAssertThrowsError(try CLIInputResolver.resolve(text: nil, fileName: fileURL.path)) { error in
            XCTAssertEqual(error as? CLIInputError, .nonUTF8File(fileURL.path))
        }
    }

    func testResolveThrowsWhenFileIsEmptyAfterCleanup() throws {
        let fileURL = try createTemporaryFile(contents: "   \n\n", fileExtension: "txt")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        XCTAssertThrowsError(try CLIInputResolver.resolve(text: nil, fileName: fileURL.path)) { error in
            XCTAssertEqual(error as? CLIInputError, .emptyFileContent(fileURL.path))
        }
    }

    func testResolveReadsPlainTextFile() throws {
        let fileURL = try createTemporaryFile(contents: "line 1\r\nline 2\rline 3", fileExtension: "txt")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let resolved = try CLIInputResolver.resolve(text: nil, fileName: fileURL.path)
        XCTAssertEqual(resolved, "line 1\nline 2\nline 3")
    }

    func testResolveCleansMarkdownFrontMatterAndComments() throws {
        let markdown = """
        ---
        title: Demo
        ---
        <!-- hidden -->
        # Hello World
        """
        let fileURL = try createTemporaryFile(contents: markdown, fileExtension: "md")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let resolved = try CLIInputResolver.resolve(text: nil, fileName: fileURL.path)
        XCTAssertEqual(resolved, "Hello World.")
    }

    func testResolveCleansMarkdownHeadingLinksListsAndCodeFences() throws {
        let markdown = """
        ## Overview
        - [x] ship [docs](https://example.com/docs)
        - keep **focus**
        https://example.com/standalone

        ```swift
        let value = 1
        ```
        """
        let fileURL = try createTemporaryFile(contents: markdown, fileExtension: "markdown")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let resolved = try CLIInputResolver.resolve(text: nil, fileName: fileURL.path)
        let expected = """
        Section: Overview
        ship docs
        keep focus
        https://example.com/standalone

        Code:
        let value = 1
        End code.
        """
        XCTAssertEqual(resolved, expected)
    }

    private func createTemporaryFile(contents: String, fileExtension: String) throws -> URL {
        let data = Data(contents.utf8)
        return try createTemporaryFile(data: data, fileExtension: fileExtension)
    }

    private func createTemporaryFile(data: Data, fileExtension: String = "txt") throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appendingPathComponent("input").appendingPathExtension(fileExtension)
        try data.write(to: fileURL)
        return fileURL
    }
}
