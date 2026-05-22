import SwiftUI

class MarkdownNSTextView: NSTextView {
    var onCommandReturn: (() -> Void)?
    weak var completionPanel: CompletionPanel?
    var onCompletionConfirm: (() -> Void)?
    var onCompletionDismiss: (() -> Void)?
    var customTopInset: CGFloat?

    override var textContainerOrigin: NSPoint {
        if let top = customTopInset {
            return NSPoint(x: textContainerInset.width, y: top)
        }
        return super.textContainerOrigin
    }

    override func keyDown(with event: NSEvent) {
        if let panel = completionPanel, panel.isVisible {
            switch event.keyCode {
            case 126: // up
                panel.moveUp()
                return
            case 125: // down
                panel.moveDown()
                return
            case 36: // return
                if event.modifierFlags.contains(.command) {
                    onCommandReturn?()
                } else {
                    onCompletionConfirm?()
                }
                return
            case 48: // tab
                onCompletionConfirm?()
                return
            case 53: // escape
                onCompletionDismiss?()
                return
            default:
                break
            }
        } else if event.modifierFlags.contains(.command) && event.keyCode == 36 {
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
    @Binding var pendingInsert: String?
    var onOpenLink: (String) -> Void
    var onCursorChange: ((Int) -> Void)?
    var onTextChange: ((String) -> Void)?
    @Binding var titleText: String
    var titleError: String?
    var onTitleCommit: (() -> Void)?
    var onTitleFocusLost: (() -> Void)?
    @Binding var needsTitleFocus: Bool

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(text: $text, titleText: $titleText, onOpenLink: onOpenLink, onCursorChange: onCursorChange, onTextChange: onTextChange, onTitleCommit: onTitleCommit, onTitleFocusLost: onTitleFocusLost)
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
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

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
        let titleFontSize = fontSize * 2.5
        let titleFont = NSFont.systemFont(ofSize: titleFontSize, weight: .semibold)
        let titleFieldY: CGFloat = 44
        let titleFieldHeight = ceil(titleFont.boundingRectForFont.height) + 8

        let titleField = NSTextField()
        titleField.stringValue = titleText
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.font = titleFont
        titleField.placeholderString = "Filename"
        titleField.focusRingType = .none
        titleField.delegate = context.coordinator
        titleField.frame = NSRect(x: 84, y: titleFieldY, width: max(100, contentSize.width - 168), height: titleFieldHeight)
        titleField.autoresizingMask = [.width]

        let errorLabel = NSTextField(labelWithString: titleError ?? "")
        errorLabel.font = NSFont.systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = titleError == nil
        errorLabel.frame = NSRect(x: 84, y: titleFieldY + titleFieldHeight + 2, width: max(100, contentSize.width - 168), height: 16)
        errorLabel.autoresizingMask = [.width]

        let titleInset = titleFieldY + titleFieldHeight + (titleError != nil ? 22 : 0) + 16
        let bottomPadding = max(400, contentSize.height / 2)
        textView.customTopInset = titleInset
        textView.textContainerInset = NSSize(width: 80, height: titleInset + bottomPadding)

        textView.addSubview(titleField)
        textView.addSubview(errorLabel)
        context.coordinator.titleField = titleField
        context.coordinator.titleErrorLabel = errorLabel

        textView.string = text
        let coordinator = context.coordinator
        textView.completionPanel = coordinator.completionPanel
        textView.onCommandReturn = { [weak coordinator] in
            coordinator?.openLinkAtCursor(in: textView)
        }
        textView.onCompletionConfirm = { [weak coordinator] in
            coordinator?.confirmCompletion(in: textView)
        }
        textView.onCompletionDismiss = { [weak coordinator] in
            coordinator?.dismissCompletion()
        }
        coordinator.completionPanel.onSelect = { [weak coordinator] _ in
            coordinator?.confirmCompletion(in: textView)
        }

        scrollView.documentView = textView

        context.coordinator.applyMarkdownStyling(to: textView)

        if needsFocus {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                self.needsFocus = false
            }
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.onOpenLink = onOpenLink
        context.coordinator.onCursorChange = onCursorChange
        context.coordinator.onTextChange = onTextChange
        context.coordinator.fileNames = fileNames
        context.coordinator.titleText = $titleText
        context.coordinator.onTitleCommit = onTitleCommit
        context.coordinator.onTitleFocusLost = onTitleFocusLost

        if needsFocus {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                self.needsFocus = false
            }
        }

        if needsTitleFocus {
            DispatchQueue.main.async {
                if let titleField = context.coordinator.titleField {
                    textView.window?.makeFirstResponder(titleField)
                    titleField.selectText(nil)
                }
                self.needsTitleFocus = false
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

        if let insertText = pendingInsert {
            self.pendingInsert = nil
            DispatchQueue.main.async {
                let range = textView.selectedRange()
                if textView.shouldChangeText(in: range, replacementString: insertText) {
                    textView.replaceCharacters(in: range, with: insertText)
                    textView.didChangeText()
                }
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

        let titleFont = NSFont.systemFont(ofSize: fontSize * 2.5, weight: .semibold)
        let tfHeight = ceil(titleFont.boundingRectForFont.height) + 8
        if let titleField = context.coordinator.titleField {
            if titleField.stringValue != titleText {
                titleField.stringValue = titleText
            }
            if fontChanged {
                titleField.font = titleFont
                titleField.frame.size.height = tfHeight
                context.coordinator.titleErrorLabel?.frame.origin.y = 44 + tfHeight + 2
            }
        }
        if let errorLabel = context.coordinator.titleErrorLabel {
            if let error = titleError {
                errorLabel.stringValue = error
                errorLabel.isHidden = false
            } else {
                errorLabel.isHidden = true
            }
        }
        let titleInset: CGFloat = 44 + tfHeight + (titleError != nil ? 22 : 0) + 16
        let bottomPadding = scrollView.contentSize.height / 3
        let totalInset = titleInset + bottomPadding
        (textView as? MarkdownNSTextView)?.customTopInset = titleInset
        if abs(textView.textContainerInset.height - totalInset) > 0.5 {
            textView.textContainerInset = NSSize(width: 80, height: totalInset)
            textView.needsLayout = true
        }

        if textView.string != text {
            textView.string = text
            context.coordinator.applyMarkdownStyling(to: textView)
        } else if fontChanged || wrapChanged || renderingChanged {
            context.coordinator.applyMarkdownStyling(to: textView)
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate, NSTextFieldDelegate {
        var text: Binding<String>
        var titleText: Binding<String>
        var onOpenLink: (String) -> Void
        var onCursorChange: ((Int) -> Void)?
        var onTextChange: ((String) -> Void)?
        var onTitleCommit: (() -> Void)?
        var onTitleFocusLost: (() -> Void)?
        var titleField: NSTextField?
        var titleErrorLabel: NSTextField?
        var fileNames: Set<String> = []
        var fontSize: CGFloat = 14
        var wordWrap: Bool = true
        var dynamicRendering: Bool = true
        let completionPanel = CompletionPanel()
        private var isUpdating = false
        private var hiddenIndices = IndexSet()

        init(text: Binding<String>, titleText: Binding<String>, onOpenLink: @escaping (String) -> Void, onCursorChange: ((Int) -> Void)?, onTextChange: ((String) -> Void)?, onTitleCommit: (() -> Void)?, onTitleFocusLost: (() -> Void)?) {
            self.text = text
            self.titleText = titleText
            self.onOpenLink = onOpenLink
            self.onCursorChange = onCursorChange
            self.onTextChange = onTextChange
            self.onTitleCommit = onTitleCommit
            self.onTitleFocusLost = onTitleFocusLost
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
            updateCompletion(in: textView)
            isUpdating = false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            isUpdating = true
            applyMarkdownStyling(to: textView)
            onCursorChange?(textView.selectedRange().location)
            if wikiLinkQuery(in: textView) == nil {
                completionPanel.hide()
            }
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

        // MARK: - Completion

        private func wikiLinkQuery(in textView: NSTextView) -> (query: String, range: NSRange)? {
            let cursor = textView.selectedRange().location
            let string = textView.string as NSString
            let searchStart = max(0, cursor - 200)
            let searchLen = cursor - searchStart
            guard searchLen > 0 else { return nil }
            let before = string.substring(with: NSRange(location: searchStart, length: searchLen))
            guard let bracketPos = before.range(of: "[[", options: .backwards) else { return nil }
            let after = before[bracketPos.upperBound...]
            if after.contains("]]") || after.contains("\n") { return nil }
            let query = String(after)
            let queryStart = searchStart + before.distance(from: before.startIndex, to: bracketPos.upperBound)
            return (query, NSRange(location: queryStart, length: cursor - queryStart))
        }

        func updateCompletion(in textView: NSTextView) {
            guard let (query, _) = wikiLinkQuery(in: textView),
                  let window = textView.window else {
                completionPanel.hide()
                return
            }

            let matches: [String]
            if query.isEmpty {
                matches = Array(fileNames.sorted().prefix(20))
            } else {
                let lowered = query.lowercased()
                matches = fileNames
                    .filter { $0.lowercased().contains(lowered) }
                    .sorted()
                    .prefix(20)
                    .map { $0 }
            }

            guard !matches.isEmpty else {
                completionPanel.hide()
                return
            }

            let cursorRange = textView.selectedRange()
            let screenRect = textView.firstRect(forCharacterRange: cursorRange, actualRange: nil)
            completionPanel.show(
                at: NSPoint(x: screenRect.origin.x, y: screenRect.origin.y),
                in: window,
                items: matches
            )
        }

        func confirmCompletion(in textView: NSTextView) {
            guard let selected = completionPanel.selectedItem(),
                  let (_, queryRange) = wikiLinkQuery(in: textView) else {
                completionPanel.hide()
                return
            }

            let string = textView.string as NSString
            let afterQuery = NSMaxRange(queryRange)
            let hasClosing = afterQuery + 2 <= string.length
                && string.substring(with: NSRange(location: afterQuery, length: 2)) == "]]"

            let replacement = selected + (hasClosing ? "" : "]]")
            if textView.shouldChangeText(in: queryRange, replacementString: replacement) {
                textView.replaceCharacters(in: queryRange, with: replacement)
                textView.didChangeText()
            }
            completionPanel.hide()
        }

        func dismissCompletion() {
            completionPanel.hide()
        }

        // MARK: - NSTextFieldDelegate (title field)

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField, field === titleField else { return }
            titleText.wrappedValue = field.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField, field === titleField else { return }
            onTitleFocusLost?()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard control === titleField else { return false }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onTitleCommit?()
                return true
            }
            return false
        }
    }
}
