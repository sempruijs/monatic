import Combine
import SwiftUI

class CompletionState: ObservableObject {
    @Published var items: [String] = []
    @Published var selectedIndex: Int = 0
    var onAccept: ((String) -> Void)?
}

struct CompletionListView: View {
    @ObservedObject var state: CompletionState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(state.items.enumerated()), id: \.offset) { index, name in
                        Text(name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(index == state.selectedIndex ? Color.accentColor : Color.clear)
                            .foregroundStyle(index == state.selectedIndex ? .white : .primary)
                            .cornerRadius(4)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                state.onAccept?(name)
                            }
                    }
                }
                .padding(4)
            }
            .onChange(of: state.selectedIndex) { _, newValue in
                proxy.scrollTo(newValue)
            }
        }
    }
}

class LinkCompletionTextView: NSTextView {
    var allFileNames: [String] = []
    var onFollowLink: ((String) -> Void)?
    let completionState = CompletionState()

    private var completionPanel: NSPanel?
    private var isCompletionVisible: Bool { completionPanel?.isVisible == true }
    private var isHandlingChange = false

    override func didChangeText() {
        guard !isHandlingChange else { return }
        isHandlingChange = true
        super.didChangeText()
        updateCompletion()
        isHandlingChange = false
    }

    override func mouseDown(with event: NSEvent) {
        dismissCompletion()
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 && event.modifierFlags.contains(.command) {
            if let linkName = linkNameAtCursor() {
                onFollowLink?(linkName)
                return
            }
        }

        if isCompletionVisible {
            switch event.keyCode {
            case 125: // down
                completionState.selectedIndex = min(
                    completionState.selectedIndex + 1,
                    completionState.items.count - 1
                )
                return
            case 126: // up
                completionState.selectedIndex = max(completionState.selectedIndex - 1, 0)
                return
            case 36, 48: // return, tab
                if !completionState.items.isEmpty {
                    acceptCompletion(completionState.items[completionState.selectedIndex])
                    return
                }
            case 53: // escape
                dismissCompletion()
                return
            case 123, 124: // left, right arrows dismiss completion
                dismissCompletion()
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    private func linkNameAtCursor() -> String? {
        let cursor = selectedRange().location
        let nsString = string as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = VaultGraph.linkPattern.matches(in: string, range: fullRange)
        for match in matches {
            let matchRange = match.range(at: 0)
            if cursor >= matchRange.location && cursor <= matchRange.location + matchRange.length {
                return nsString.substring(with: match.range(at: 1))
            }
        }
        return nil
    }

    private func updateCompletion() {
        let cursorLocation = selectedRange().location
        guard cursorLocation >= 2 else {
            dismissCompletion()
            return
        }

        let textUpToCursor = (string as NSString).substring(to: cursorLocation)

        guard let openRange = textUpToCursor.range(of: "[[", options: .backwards) else {
            dismissCompletion()
            return
        }

        let afterOpen = String(textUpToCursor[openRange.upperBound...])
        if afterOpen.contains("]]") || afterOpen.contains("\n") {
            dismissCompletion()
            return
        }

        let query = afterOpen
        let filtered: ArraySlice<String>
        if query.isEmpty {
            filtered = allFileNames.prefix(20)
        } else {
            filtered = allFileNames.lazy.filter { $0.localizedCaseInsensitiveContains(query) }.prefix(20)
        }

        if filtered.isEmpty {
            dismissCompletion()
            return
        }

        let items = Array(filtered)
        if completionState.items != items {
            completionState.items = items
            completionState.selectedIndex = 0
        }
        showCompletionPanel()
    }

    private func showCompletionPanel() {
        if completionPanel == nil {
            setupCompletionPanel()
        }

        guard window != nil else { return }

        var actualRange = selectedRange()
        let cursorScreenRect = firstRect(forCharacterRange: selectedRange(), actualRange: &actualRange)

        let panelHeight = min(CGFloat(completionState.items.count) * 28 + 8, 200)
        completionPanel?.setFrame(
            NSRect(
                x: cursorScreenRect.origin.x,
                y: cursorScreenRect.origin.y - panelHeight,
                width: 300,
                height: panelHeight
            ),
            display: true
        )
        if !isCompletionVisible {
            completionPanel?.orderFront(nil)
        }
    }

    private func setupCompletionPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.backgroundColor = .clear
        panel.hasShadow = true

        completionState.onAccept = { [weak self] name in
            self?.acceptCompletion(name)
        }

        let hostingView = NSHostingView(
            rootView: CompletionListView(state: completionState)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        )
        panel.contentView = hostingView

        completionPanel = panel
    }

    private func acceptCompletion(_ name: String) {
        let cursorLocation = selectedRange().location
        let textUpToCursor = (string as NSString).substring(to: cursorLocation)

        guard let openRange = textUpToCursor.range(of: "[[", options: .backwards) else { return }

        let replaceStart = textUpToCursor.distance(from: textUpToCursor.startIndex, to: openRange.upperBound)
        let replaceRange = NSRange(location: replaceStart, length: cursorLocation - replaceStart)
        let replacement = "\(name)]]"

        if shouldChangeText(in: replaceRange, replacementString: replacement) {
            replaceCharacters(in: replaceRange, with: replacement)
            setSelectedRange(NSRange(location: replaceStart + replacement.count, length: 0))
            didChangeText()
        }

        dismissCompletion()
    }

    func dismissCompletion() {
        completionPanel?.orderOut(nil)
    }
}

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var fileNames: [String]
    var fontSize: CGFloat = 14
    var wordWrap: Bool = true
    var onOpenLink: (String) -> Void
    var onTextChange: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(text: $text, onOpenLink: onOpenLink, onTextChange: onTextChange)
        coordinator.fontSize = fontSize
        coordinator.wordWrap = wordWrap
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
        textStorage.addLayoutManager(layoutManager)
        let containerWidth = wordWrap ? contentSize.width : CGFloat.greatestFiniteMagnitude
        let textContainer = NSTextContainer(size: NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = wordWrap
        layoutManager.addTextContainer(textContainer)

        let textView = LinkCompletionTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
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
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.string = text
        textView.allFileNames = fileNames
        textView.onFollowLink = { name in context.coordinator.onOpenLink(name) }

        scrollView.documentView = textView

        context.coordinator.applyLinkStyling(to: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? LinkCompletionTextView else { return }
        textView.allFileNames = fileNames
        context.coordinator.onOpenLink = onOpenLink
        context.coordinator.onTextChange = onTextChange
        textView.onFollowLink = { name in context.coordinator.onOpenLink(name) }

        let fontChanged = context.coordinator.fontSize != fontSize
        context.coordinator.fontSize = fontSize

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
            context.coordinator.applyLinkStyling(to: textView)
        } else if fontChanged || wrapChanged {
            context.coordinator.applyLinkStyling(to: textView)
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onOpenLink: (String) -> Void
        var onTextChange: ((String) -> Void)?
        var fontSize: CGFloat = 14
        var wordWrap: Bool = true
        private var isUpdating = false

        init(text: Binding<String>, onOpenLink: @escaping (String) -> Void, onTextChange: ((String) -> Void)?) {
            self.text = text
            self.onOpenLink = onOpenLink
            self.onTextChange = onTextChange
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            isUpdating = true
            let content = textView.string
            text.wrappedValue = content
            onTextChange?(content)
            applyLinkStyling(to: textView)
            isUpdating = false
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL, url.scheme == "linker" {
                let filename = url.host() ?? ""
                let decoded = filename.removingPercentEncoding ?? filename
                onOpenLink(decoded)
                return true
            }
            return false
        }

        func applyLinkStyling(to textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            let string = textStorage.string
            let fullRange = NSRange(location: 0, length: textStorage.length)

            textStorage.beginEditing()
            textStorage.removeAttribute(.link, range: fullRange)
            textStorage.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)
            textStorage.addAttribute(
                .font,
                value: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                range: fullRange
            )

            let pattern = "\\[\\[([^\\]]+)\\]\\]"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                for match in regex.matches(in: string, range: fullRange) {
                    let matchRange = match.range(at: 0)
                    let innerRange = match.range(at: 1)
                    let innerText = (string as NSString).substring(with: innerRange)
                    let encoded = innerText.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? innerText
                    if let url = URL(string: "linker://\(encoded)") {
                        textStorage.addAttribute(.link, value: url, range: matchRange)
                    }
                }
            }
            textStorage.endEditing()
        }
    }
}
