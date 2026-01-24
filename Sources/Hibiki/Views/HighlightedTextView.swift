import SwiftUI

struct HighlightedTextView: View {
    let text: String
    let highlightIndex: Int
    let highlightColor: Color

    var body: some View {
        Text(attributedText)
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .textSelection(.enabled)
    }

    private var attributedText: AttributedString {
        guard !text.isEmpty else {
            return AttributedString(" ")
        }

        var attributed = AttributedString(text)

        // Find the character range at the highlight index
        let charRange = findCharacterRange(at: highlightIndex)

        // Apply styling to already-read portion (dimmed)
        if let beforeRange = charRange.beforeRange {
            attributed[beforeRange].foregroundColor = .secondary.opacity(0.6)
        }

        // Apply highlight to current character
        if let currentRange = charRange.currentRange {
            attributed[currentRange].backgroundColor = highlightColor.opacity(0.3)
            attributed[currentRange].foregroundColor = .primary
        }

        // Text after current character remains normal
        if let afterRange = charRange.afterRange {
            attributed[afterRange].foregroundColor = .primary.opacity(0.9)
        }

        return attributed
    }

    private struct WordRanges {
        var beforeRange: Range<AttributedString.Index>?
        var currentRange: Range<AttributedString.Index>?
        var afterRange: Range<AttributedString.Index>?
    }

    private func findCharacterRange(at characterIndex: Int) -> WordRanges {
        var ranges = WordRanges()

        guard !text.isEmpty else { return ranges }

        // Clamp the index to valid range
        let clampedIndex = max(0, min(characterIndex, text.count - 1))

        // Convert to String.Index for the single character
        let charStart = text.index(text.startIndex, offsetBy: clampedIndex)
        let charEnd = text.index(after: charStart)

        // Create AttributedString indices
        let attrStr = AttributedString(text)
        let attrStart = AttributedString.Index(charStart, within: attrStr)!
        let attrEnd = AttributedString.Index(charEnd, within: attrStr)!
        let attrTextStart = attrStr.startIndex
        let attrTextEnd = attrStr.endIndex

        // Set ranges
        if attrStart > attrTextStart {
            ranges.beforeRange = attrTextStart..<attrStart
        }

        ranges.currentRange = attrStart..<attrEnd

        if attrEnd < attrTextEnd {
            ranges.afterRange = attrEnd..<attrTextEnd
        }

        return ranges
    }
}

#Preview {
    VStack(spacing: 20) {
        HighlightedTextView(
            text: "This is a sample text that demonstrates the highlighting feature.",
            highlightIndex: 15,
            highlightColor: .blue
        )
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)

        HighlightedTextView(
            text: "Another example with orange highlighting for summarization mode.",
            highlightIndex: 30,
            highlightColor: .orange
        )
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    .padding()
}
