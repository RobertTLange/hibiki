import XCTest
import AppKit
@testable import Hibiki

final class PasteboardSnapshotTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private let custom = NSPasteboard.PasteboardType("com.example.custom-binary")

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard.withUniqueName()
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        super.tearDown()
    }

    /// Regression: the Cmd+C fallback saved only the plain string, so an image, file or
    /// rich-text clipboard was destroyed and a concealed password lost its marker.
    func testRestoreBringsBackEveryRepresentation() {
        let item = NSPasteboardItem()
        item.setString("secret", forType: .string)
        item.setData(Data("{\\rtf1 secret}".utf8), forType: .rtf)
        item.setData(Data([0x00, 0xFF, 0x10]), forType: custom)
        item.setString("", forType: concealed)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        let snapshot = PasteboardSnapshot(of: pasteboard)

        // What the simulated copy does to the clipboard.
        pasteboard.clearContents()
        pasteboard.setString("selected text", forType: .string)

        snapshot.restore(to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "secret")
        XCTAssertEqual(pasteboard.data(forType: .rtf), Data("{\\rtf1 secret}".utf8))
        XCTAssertEqual(pasteboard.data(forType: custom), Data([0x00, 0xFF, 0x10]))
        XCTAssertTrue(pasteboard.types?.contains(concealed) == true)
    }

    func testRestoreKeepsMultipleItems() {
        let first = NSPasteboardItem()
        first.setString("one", forType: .string)
        let second = NSPasteboardItem()
        second.setString("two", forType: .string)
        pasteboard.clearContents()
        pasteboard.writeObjects([first, second])

        let snapshot = PasteboardSnapshot(of: pasteboard)
        pasteboard.clearContents()
        snapshot.restore(to: pasteboard)

        XCTAssertEqual(pasteboard.pasteboardItems?.compactMap { $0.string(forType: .string) }, ["one", "two"])
    }

    func testRestoringAnEmptyClipboardLeavesItEmpty() {
        pasteboard.clearContents()
        let snapshot = PasteboardSnapshot(of: pasteboard)
        XCTAssertTrue(snapshot.isEmpty)

        pasteboard.setString("selected text", forType: .string)
        snapshot.restore(to: pasteboard)

        XCTAssertNil(pasteboard.string(forType: .string))
    }
}
