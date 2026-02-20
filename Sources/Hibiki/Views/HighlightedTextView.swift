import SwiftUI

struct HighlightedTextView: NSViewRepresentable {
    let text: String
    let highlightIndex: Int
    let highlightColor: Color

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        context.coordinator.attach(to: scrollView)

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.usesFontPanel = false
        textView.usesFindBar = false
        textView.allowsUndo = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = NSFont.systemFont(ofSize: 12)
        textView.textColor = NSColor.labelColor
        textView.layoutManager?.usesFontLeading = true

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        textView.textContainer?.containerSize = NSSize(width: nsView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        let clampedIndex = clampedHighlightIndex(for: text, highlightIndex: highlightIndex)
        let highlightNSColor = NSColor(highlightColor)
        let isNewRun = context.coordinator.lastText != text || clampedIndex < context.coordinator.lastHighlightIndex
        if isNewRun {
            context.coordinator.followHighlight = true
        }

        if context.coordinator.lastText != text || context.coordinator.lastHighlightIndex < 0 {
            textView.textStorage?.setAttributedString(
                makeAttributedText(text: text, highlightIndex: clampedIndex, highlightColor: highlightNSColor)
            )
        } else if clampedIndex < context.coordinator.lastHighlightIndex {
            textView.textStorage?.setAttributedString(
                makeAttributedText(text: text, highlightIndex: clampedIndex, highlightColor: highlightNSColor)
            )
        } else if clampedIndex != context.coordinator.lastHighlightIndex {
            updateHighlight(
                in: textView,
                text: text,
                from: context.coordinator.lastHighlightIndex,
                to: clampedIndex,
                highlightColor: highlightNSColor
            )
        }

        context.coordinator.lastText = text
        context.coordinator.lastHighlightIndex = clampedIndex

        if context.coordinator.followHighlight {
            scrollHighlightIntoView(textView: textView, text: text, highlightIndex: clampedIndex, coordinator: context.coordinator)
        }
    }

    // MARK: - Helpers

    private func clampedHighlightIndex(for text: String, highlightIndex: Int) -> Int {
        guard !text.isEmpty else { return 0 }
        return max(0, min(highlightIndex, text.count - 1))
    }

    private func baseAttributes() -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.minimumLineHeight = 16
        paragraphStyle.maximumLineHeight = 16

        return [
            .font: NSFont.systemFont(ofSize: 12),
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.9),
            .backgroundColor: NSColor.clear
        ]
    }

    private func beforeAttributes() -> [NSAttributedString.Key: Any] {
        return [
            .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.6),
            .backgroundColor: NSColor.clear
        ]
    }

    private func highlightAttributes(color: NSColor) -> [NSAttributedString.Key: Any] {
        return [
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: color.withAlphaComponent(0.3)
        ]
    }

    private func makeAttributedText(text: String, highlightIndex: Int, highlightColor: NSColor) -> NSAttributedString {
        let displayText = text.isEmpty ? " " : text
        let attributed = NSMutableAttributedString(string: displayText, attributes: baseAttributes())

        guard !text.isEmpty else {
            return attributed
        }

        let (beforeRange, currentRange, afterRange) = ranges(for: text, highlightIndex: highlightIndex)

        if let beforeRange {
            attributed.addAttributes(beforeAttributes(), range: beforeRange)
        }

        if let currentRange {
            attributed.addAttributes(highlightAttributes(color: highlightColor), range: currentRange)
        }

        if let afterRange {
            attributed.addAttributes(baseAttributes(), range: afterRange)
        }

        return attributed
    }

    private func updateHighlight(
        in textView: NSTextView,
        text: String,
        from oldIndex: Int,
        to newIndex: Int,
        highlightColor: NSColor
    ) {
        guard let textStorage = textView.textStorage else { return }
        guard !text.isEmpty else { return }

        let safeOld = max(0, min(oldIndex, text.count - 1))
        let safeNew = max(0, min(newIndex, text.count - 1))
        if safeNew == safeOld {
            return
        }

        let (_, currentRange, _) = ranges(for: text, highlightIndex: safeNew)

        textStorage.beginEditing()
        if safeNew > safeOld {
            let rangeStart = text.index(text.startIndex, offsetBy: safeOld)
            let rangeEnd = text.index(text.startIndex, offsetBy: safeNew)
            let progressedRange = NSRange(rangeStart..<rangeEnd, in: text)
            textStorage.addAttributes(beforeAttributes(), range: progressedRange)
        }

        if let currentRange {
            textStorage.addAttributes(highlightAttributes(color: highlightColor), range: currentRange)
        }
        textStorage.endEditing()
    }

    private func ranges(for text: String, highlightIndex: Int)
        -> (before: NSRange?, current: NSRange?, after: NSRange?) {
        guard !text.isEmpty else { return (nil, nil, nil) }

        let clampedIndex = max(0, min(highlightIndex, text.count - 1))
        let startIndex = text.index(text.startIndex, offsetBy: clampedIndex)
        let endIndex = text.index(after: startIndex)

        let currentRange = NSRange(startIndex..<endIndex, in: text)
        let beforeRange = startIndex > text.startIndex
            ? NSRange(text.startIndex..<startIndex, in: text)
            : nil
        let afterRange = endIndex < text.endIndex
            ? NSRange(endIndex..<text.endIndex, in: text)
            : nil

        return (beforeRange, currentRange, afterRange)
    }

    private func scrollHighlightIntoView(
        textView: NSTextView,
        text: String,
        highlightIndex: Int,
        coordinator: Coordinator
    ) {
        guard let scrollView = textView.enclosingScrollView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              !text.isEmpty
        else { return }

        let clampedIndex = max(0, min(highlightIndex, text.count - 1))
        let startIndex = text.index(text.startIndex, offsetBy: clampedIndex)
        let endIndex = text.index(after: startIndex)
        let range = NSRange(startIndex..<endIndex, in: text)

        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        if glyphRect.isEmpty {
            glyphRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        }
        let containerOrigin = textView.textContainerOrigin
        let highlightRect = glyphRect.offsetBy(dx: containerOrigin.x, dy: containerOrigin.y)

        let clipView = scrollView.contentView
        let visibleRect = clipView.bounds
        let targetMidY = highlightRect.midY - visibleRect.height / 2
        let usedRect = layoutManager.usedRect(for: textContainer)
        let contentHeight = max(usedRect.height + textView.textContainerInset.height * 2, visibleRect.height)
        if abs(textView.frame.height - contentHeight) > 1 {
            textView.frame.size.height = contentHeight
        }
        let maxY = max(0, contentHeight - visibleRect.height)
        let clampedY = max(0, min(targetMidY, maxY))

        if abs(clampedY - visibleRect.origin.y) < 1 {
            return
        }

        coordinator.isProgrammaticScroll = true
        clipView.setBoundsOrigin(NSPoint(x: 0, y: clampedY))
        scrollView.reflectScrolledClipView(clipView)
        coordinator.isProgrammaticScroll = false
    }

    final class Coordinator {
        var lastText: String = ""
        var lastHighlightIndex: Int = -1
        var followHighlight: Bool = true
        var isProgrammaticScroll: Bool = false
        private var scrollObserver: NSObjectProtocol?
        private weak var observedScrollView: NSScrollView?

        deinit {
            detach()
        }

        func attach(to scrollView: NSScrollView) {
            guard observedScrollView !== scrollView else { return }
            detach()
            observedScrollView = scrollView

            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSScrollView.didLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                if !self.isProgrammaticScroll {
                    self.followHighlight = false
                }
            }
        }

        private func detach() {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
                self.scrollObserver = nil
            }
            observedScrollView = nil
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        HighlightedTextView(
            text: "This is a sample text that demonstrates the highlighting feature.",
            highlightIndex: 15,
            highlightColor: .blue
        )
        .frame(height: 80)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)

        HighlightedTextView(
            text: "Another example with orange highlighting for summarization mode.",
            highlightIndex: 30,
            highlightColor: .orange
        )
        .frame(height: 80)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    .padding()
}
