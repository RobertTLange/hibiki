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

        // Find the word boundaries around the highlight index
        let wordRange = findWordRange(around: highlightIndex)

        // Apply styling to already-read portion (dimmed)
        if let beforeRange = wordRange.beforeRange {
            attributed[beforeRange].foregroundColor = .secondary.opacity(0.6)
        }

        // Apply highlight to current word
        if let currentRange = wordRange.currentRange {
            attributed[currentRange].backgroundColor = highlightColor.opacity(0.3)
            attributed[currentRange].foregroundColor = .primary
        }

        // Text after current word remains normal
        if let afterRange = wordRange.afterRange {
            attributed[afterRange].foregroundColor = .primary.opacity(0.9)
        }

        return attributed
    }

    private struct WordRanges {
        var beforeRange: Range<AttributedString.Index>?
        var currentRange: Range<AttributedString.Index>?
        var afterRange: Range<AttributedString.Index>?
    }

    private func findWordRange(around characterIndex: Int) -> WordRanges {
        var ranges = WordRanges()

        guard !text.isEmpty else { return ranges }

        // Clamp the index to valid range
        let clampedIndex = max(0, min(characterIndex, text.count - 1))

        // Convert to String.Index
        let stringIndex = text.index(text.startIndex, offsetBy: clampedIndex)

        // Find word start (scan backward to find whitespace or start)
        var wordStart = stringIndex
        while wordStart > text.startIndex {
            let prevIndex = text.index(before: wordStart)
            if text[prevIndex].isWhitespace {
                break
            }
            wordStart = prevIndex
        }

        // Find word end (scan forward to find whitespace or end)
        var wordEnd = stringIndex
        while wordEnd < text.endIndex {
            if text[wordEnd].isWhitespace {
                break
            }
            wordEnd = text.index(after: wordEnd)
        }

        // Create AttributedString indices
        let attrStart = AttributedString.Index(wordStart, within: AttributedString(text))!
        let attrEnd = AttributedString.Index(wordEnd, within: AttributedString(text))!
        let attrTextStart = AttributedString(text).startIndex
        let attrTextEnd = AttributedString(text).endIndex

        // Set ranges
        if attrStart > attrTextStart {
            ranges.beforeRange = attrTextStart..<attrStart
        }

        if attrStart < attrEnd {
            ranges.currentRange = attrStart..<attrEnd
        }

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
