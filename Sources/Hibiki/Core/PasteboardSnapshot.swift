import AppKit

/// Everything on a pasteboard, every item and every representation, so it can be put back.
///
/// Saving only the plain string loses images, files and rich text, and strips markers such
/// as `org.nspasteboard.ConcealedType` that password managers put next to a secret.
struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(of pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var representations: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    representations[type] = data
                }
            }
            return representations
        }
    }

    var isEmpty: Bool { items.allSatisfy(\.isEmpty) }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored: [NSPasteboardItem] = items.compactMap { representations in
            guard !representations.isEmpty else { return nil }
            let item = NSPasteboardItem()
            for (type, data) in representations {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restored.isEmpty {
            pasteboard.writeObjects(restored)
        }
    }
}
