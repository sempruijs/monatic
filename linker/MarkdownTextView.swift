import SwiftUI

private class MarkdownNSTextView: NSTextView {
    var onCommandReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) && event.keyCode == 36 {
            onCommandReturn?()
            return
        }
        super.keyDown(with: event)
    }
}

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var fileNames: Set<String>
    var fontSize: CGFloat
    var wordWrap: Bool
    var dynamicRendering: Bool
    @Binding var cursorPositionToRestore: Int?
    @Binding var needsFocus: Bool
    var onOpenLink: (String) -> Void
    var onCursorChange: ((Int) -> Void)?
    var onTextChange: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(text: $text, onOpenLink: onOpenLink, onCursorChange: onCursorChange, onTextChange: onTextChange)
        coordinator.fontSize = fontSize
        coordinator.wordWrap = wordWrap
        coordinator.dynamicRendering = dynamicRendering
        coordinator.fileNames = fileNames
        return coordinator
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = !wordWrap
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let contentSize = scrollView.contentSize

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.delegate = context.coordinator
        textStorage.addLayoutManager(layoutManager)
        let containerWidth = wordWrap ? contentSize.width : CGFloat.greatestFiniteMagnitude
        let textContainer = NSTextContainer(size: NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = wordWrap
        layoutManager.addTextContainer(textContainer)

        let textView = MarkdownNSTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = !wordWrap
        textView.autoresizingMask = wordWrap ? [.width] : []
        textView.delegate = context.coordinator
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.isAutomaticLinkDetectionEnabled = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.linkTextAttributes = [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.string = text
        let coordinator = context.coordinator
        textView.onCommandReturn = { [weak coordinator] in
            coordinator?.openLinkAtCursor(in: textView)
        }

        scrollView.documentView = textView

        context.coordinator.applyMarkdownStyling(to: textView)

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.onOpenLink = onOpenLink
        context.coordinator.onCursorChange = onCursorChange
        context.coordinator.onTextChange = onTextChange
        context.coordinator.fileNames = fileNames

        if needsFocus {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                self.needsFocus = false
            }
        }

        if let position = cursorPositionToRestore {
            DispatchQueue.main.async {
                let safe = min(position, textView.string.count)
                textView.setSelectedRange(NSRange(location: safe, length: 0))
                textView.scrollRangeToVisible(NSRange(location: safe, length: 0))
                self.cursorPositionToRestore = nil
            }
        }

        let fontChanged = context.coordinator.fontSize != fontSize
        context.coordinator.fontSize = fontSize

        let renderingChanged = context.coordinator.dynamicRendering != dynamicRendering
        context.coordinator.dynamicRendering = dynamicRendering

        let wrapChanged = context.coordinator.wordWrap != wordWrap
        context.coordinator.wordWrap = wordWrap

        if wrapChanged {
            scrollView.hasHorizontalScroller = !wordWrap
            if let textContainer = textView.textContainer {
                textContainer.widthTracksTextView = wordWrap
                textContainer.size = NSSize(
                    width: wordWrap ? scrollView.contentSize.width : CGFloat.greatestFiniteMagnitude,
                    height: CGFloat.greatestFiniteMagnitude
                )
            }
            textView.isHorizontallyResizable = !wordWrap
            textView.autoresizingMask = wordWrap ? [.width] : []
            if wordWrap {
                textView.frame.size.width = scrollView.contentSize.width
            }
            textView.needsLayout = true
        }

        if textView.string != text {
            textView.string = text
            context.coordinator.applyMarkdownStyling(to: textView)
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        } else if fontChanged || wrapChanged || renderingChanged {
            context.coordinator.applyMarkdownStyling(to: textView)
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
        var text: Binding<String>
        var onOpenLink: (String) -> Void
        var onCursorChange: ((Int) -> Void)?
        var onTextChange: ((String) -> Void)?
        var fileNames: Set<String> = []
        var fontSize: CGFloat = 14
        var wordWrap: Bool = true
        var dynamicRendering: Bool = true
        private var isUpdating = false
        private var hiddenIndices = IndexSet()

        init(text: Binding<String>, onOpenLink: @escaping (String) -> Void, onCursorChange: ((Int) -> Void)?, onTextChange: ((String) -> Void)?) {
            self.text = text
            self.onOpenLink = onOpenLink
            self.onCursorChange = onCursorChange
            self.onTextChange = onTextChange
        }

        // MARK: - NSLayoutManagerDelegate

        func layoutManager(
            _ layoutManager: NSLayoutManager,
            shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
            properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
            characterIndexes charIndexes: UnsafePointer<Int>,
            font aFont: NSFont,
            forGlyphRange glyphRange: NSRange
        ) -> Int {
            var needsChange = false
            for i in 0..<glyphRange.length {
                if hiddenIndices.contains(charIndexes[i]) {
                    needsChange = true
                    break
                }
            }
            guard needsChange else { return 0 }

            let modified = UnsafeMutablePointer<NSLayoutManager.GlyphProperty>.allocate(capacity: glyphRange.length)
            defer { modified.deallocate() }
            for i in 0..<glyphRange.length {
                modified[i] = hiddenIndices.contains(charIndexes[i]) ? .null : props[i]
            }
            layoutManager.setGlyphs(glyphs, properties: modified, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
            return glyphRange.length
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            isUpdating = true
            let content = textView.string
            text.wrappedValue = content
            onTextChange?(content)
            applyMarkdownStyling(to: textView)
            isUpdating = false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            isUpdating = true
            applyMarkdownStyling(to: textView)
            onCursorChange?(textView.selectedRange().location)
            isUpdating = false
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL else { return false }
            if url.scheme == "wikilink" {
                let name = (url.host() ?? "").removingPercentEncoding ?? ""
                onOpenLink(name)
                return true
            }
            NSWorkspace.shared.open(url)
            return true
        }

        func openLinkAtCursor(in textView: NSTextView) {
            let cursor = textView.selectedRange().location
            let string = textView.string as NSString
            let fullRange = NSRange(location: 0, length: string.length)

            for match in Self.wikiLinkRegex.matches(in: textView.string, range: fullRange) {
                let matchRange = match.range(at: 0)
                if cursor >= matchRange.location && cursor <= NSMaxRange(matchRange) {
                    let name = string.substring(with: match.range(at: 1))
                    onOpenLink(name)
                    return
                }
            }

            for match in Self.markdownLinkRegex.matches(in: textView.string, range: fullRange) {
                let matchRange = match.range(at: 0)
                if cursor >= matchRange.location && cursor <= NSMaxRange(matchRange) {
                    let urlString = string.substring(with: match.range(at: 2))
                    if let url = URL(string: urlString) {
                        NSWorkspace.shared.open(url)
                    }
                    return
                }
            }
        }

        // MARK: - Styling

        private static let headingRegex = try! NSRegularExpression(pattern: "^(#{1,5})\\s+(.+)$", options: .anchorsMatchLines)
        private static let wikiLinkRegex = try! NSRegularExpression(pattern: "\\[\\[([^\\]]+)\\]\\]")
        private static let markdownLinkRegex = try! NSRegularExpression(pattern: "(?<!\\[)\\[([^\\[\\]]+)\\]\\(([^)]+)\\)")
        private static let boldRegex = try! NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*")
        private static let italicRegex = try! NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)|(?<!\\w)_(.+?)_(?!\\w)")
        private static let headingScales: [CGFloat] = [2.0, 1.7, 1.4, 1.2, 1.1]

        private func cursorInside(_ cursor: Int, _ range: NSRange) -> Bool {
            cursor >= range.location && cursor <= NSMaxRange(range)
        }

        func applyMarkdownStyling(to textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            let string = textStorage.string
            let fullRange = NSRange(location: 0, length: textStorage.length)
            let cursor = textView.selectedRange().location
            let nsString = string as NSString

            var newHidden = IndexSet()

            textStorage.beginEditing()
            textStorage.removeAttribute(.link, range: fullRange)
            textStorage.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)
            textStorage.addAttribute(
                .font,
                value: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                range: fullRange
            )

            let existingColor = NSColor.systemBlue
            let missingColor = NSColor.systemBlue.withAlphaComponent(0.4)
            for match in Self.wikiLinkRegex.matches(in: string, range: fullRange) {
                let matchRange = match.range(at: 0)
                let innerRange = match.range(at: 1)
                let linkName = nsString.substring(with: innerRange)
                let color = fileNames.contains(linkName) ? existingColor : missingColor
                let encoded = linkName.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? linkName
                if let url = URL(string: "wikilink://\(encoded)") {
                    textStorage.addAttribute(.link, value: url, range: innerRange)
                }
                textStorage.addAttribute(.foregroundColor, value: color, range: innerRange)
                if dynamicRendering && !cursorInside(cursor, matchRange) {
                    newHidden.insert(integersIn: matchRange.location..<(matchRange.location + 2))
                    newHidden.insert(integersIn: (NSMaxRange(matchRange) - 2)..<NSMaxRange(matchRange))
                }
            }

            for match in Self.markdownLinkRegex.matches(in: string, range: fullRange) {
                let matchRange = match.range(at: 0)
                let textRange = match.range(at: 1)
                let urlRange = match.range(at: 2)
                let urlString = nsString.substring(with: urlRange)
                if let url = URL(string: urlString) {
                    textStorage.addAttribute(.link, value: url, range: textRange)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: textRange)
                }
                if dynamicRendering && !cursorInside(cursor, matchRange) {
                    newHidden.insert(matchRange.location)
                    let tailStart = NSMaxRange(textRange)
                    newHidden.insert(integersIn: tailStart..<NSMaxRange(matchRange))
                }
            }

            guard dynamicRendering else {
                hiddenIndices = newHidden
                textStorage.endEditing()
                if let lm = textView.layoutManager {
                    lm.invalidateGlyphs(forCharacterRange: fullRange, changeInLength: 0, actualCharacterRange: nil)
                    lm.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
                }
                return
            }

            for match in Self.headingRegex.matches(in: string, range: fullRange) {
                let matchRange = match.range(at: 0)
                let hashRange = match.range(at: 1)
                let textRange = match.range(at: 2)
                let level = hashRange.length
                let scale = Self.headingScales[min(level, Self.headingScales.count) - 1]
                let headingSize = fontSize * scale
                let headingFont = NSFont.monospacedSystemFont(ofSize: headingSize, weight: .bold)
                textStorage.addAttribute(.font, value: headingFont, range: textRange)
                textStorage.addAttribute(.font, value: headingFont, range: hashRange)
                if !cursorInside(cursor, matchRange) {
                    let spaceAfterHash = NSRange(location: NSMaxRange(hashRange), length: textRange.location - NSMaxRange(hashRange))
                    newHidden.insert(integersIn: hashRange.location..<NSMaxRange(hashRange))
                    newHidden.insert(integersIn: spaceAfterHash.location..<NSMaxRange(spaceAfterHash))
                }
            }

            for match in Self.boldRegex.matches(in: string, range: fullRange) {
                let matchRange = match.range(at: 0)
                let innerRange = match.range(at: 1)
                textStorage.addAttribute(
                    .font,
                    value: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold),
                    range: innerRange
                )
                if !cursorInside(cursor, matchRange) {
                    newHidden.insert(integersIn: matchRange.location..<(matchRange.location + 2))
                    newHidden.insert(integersIn: (NSMaxRange(matchRange) - 2)..<NSMaxRange(matchRange))
                }
            }

            for match in Self.italicRegex.matches(in: string, range: fullRange) {
                let matchRange = match.range(at: 0)
                let group1 = match.range(at: 1)
                let group2 = match.range(at: 2)
                let innerRange = group1.location != NSNotFound ? group1 : group2
                guard innerRange.location != NSNotFound else { continue }
                let currentFont = textStorage.attribute(.font, at: innerRange.location, effectiveRange: nil) as? NSFont
                let isBold = currentFont?.fontDescriptor.symbolicTraits.contains(.bold) == true
                let baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: isBold ? .bold : .regular)
                let desc = baseFont.fontDescriptor.withSymbolicTraits(.italic)
                let italicFont = NSFont(descriptor: desc, size: fontSize) ?? baseFont
                textStorage.addAttribute(.font, value: italicFont, range: innerRange)
                if !cursorInside(cursor, matchRange) {
                    newHidden.insert(matchRange.location)
                    newHidden.insert(NSMaxRange(matchRange) - 1)
                }
            }

            hiddenIndices = newHidden
            textStorage.endEditing()

            if let lm = textView.layoutManager {
                lm.invalidateGlyphs(forCharacterRange: fullRange, changeInLength: 0, actualCharacterRange: nil)
                lm.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
            }
        }
    }
}
