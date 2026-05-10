import Combine
import SwiftUI

// MARK: - VaultGraph

@Observable
class VaultGraph {
    struct FileEntry {
        let name: String
        let url: URL
    }

    private(set) var files: [FileEntry] = []
    private var filesByName: [String: FileEntry] = [:]
    private var outLinks: [String: Set<String>] = [:]
    private var inLinks: [String: Set<String>] = [:]

    private static let linkPattern = try! NSRegularExpression(pattern: "\\[\\[([^\\]]+)\\]\\]")

    var sortedNames: [String] { files.map(\.name) }

    func build(from vaultURL: URL) {
        filesByName.removeAll()
        outLinks.removeAll()
        inLinks.removeAll()

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: vaultURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let url as URL in enumerator {
            guard url.pathExtension == "md" else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            filesByName[name] = FileEntry(name: name, url: url)

            if let content = try? String(contentsOf: url, encoding: .utf8) {
                let links = Self.parseLinks(from: content)
                outLinks[name] = links
                for link in links {
                    inLinks[link, default: []].insert(name)
                }
            }
        }

        files = filesByName.values.sorted {
            $0.name.localizedCompare($1.name) == .orderedAscending
        }
    }

    func search(_ query: String) -> [FileEntry] {
        if query.isEmpty { return files }
        return files.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    func url(for name: String) -> URL? {
        filesByName[name]?.url
    }

    func outgoing(from name: String) -> Set<String> {
        outLinks[name] ?? []
    }

    func incoming(to name: String) -> Set<String> {
        inLinks[name] ?? []
    }

    func addFile(name: String, url: URL) {
        let entry = FileEntry(name: name, url: url)
        filesByName[name] = entry
        files = filesByName.values.sorted {
            $0.name.localizedCompare($1.name) == .orderedAscending
        }
    }

    func rename(from oldName: String, to newName: String, newURL: URL) {
        guard let entry = filesByName.removeValue(forKey: oldName) else { return }
        filesByName[newName] = FileEntry(name: newName, url: newURL)

        if let links = outLinks.removeValue(forKey: oldName) {
            outLinks[newName] = links
            for link in links {
                inLinks[link]?.remove(oldName)
                inLinks[link, default: []].insert(newName)
            }
        }

        if let backrefs = inLinks.removeValue(forKey: oldName) {
            inLinks[newName] = backrefs
        }

        files = filesByName.values.sorted {
            $0.name.localizedCompare($1.name) == .orderedAscending
        }
    }

    func updateLinks(for name: String, content: String) {
        let oldLinks = outLinks[name] ?? []
        let newLinks = Self.parseLinks(from: content)
        guard oldLinks != newLinks else { return }

        for link in oldLinks where !newLinks.contains(link) {
            inLinks[link]?.remove(name)
        }
        for link in newLinks where !oldLinks.contains(link) {
            inLinks[link, default: []].insert(name)
        }
        outLinks[name] = newLinks
    }

    private static func parseLinks(from content: String) -> Set<String> {
        let nsContent = content as NSString
        let range = NSRange(location: 0, length: nsContent.length)
        let matches = linkPattern.matches(in: content, range: range)
        var links = Set<String>()
        for match in matches {
            links.insert(nsContent.substring(with: match.range(at: 1)))
        }
        return links
    }
}

// MARK: - Completion

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

// MARK: - LinkCompletionTextView

class LinkCompletionTextView: NSTextView {
    var allFileNames: [String] = []
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

// MARK: - MarkdownTextView

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var fileNames: [String]
    var onOpenLink: (String) -> Void
    var onTextChange: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onOpenLink: onOpenLink, onTextChange: onTextChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let contentSize = scrollView.contentSize

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = LinkCompletionTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.isAutomaticLinkDetectionEnabled = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.string = text
        textView.allFileNames = fileNames

        scrollView.documentView = textView

        context.coordinator.applyLinkStyling(to: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? LinkCompletionTextView else { return }
        textView.allFileNames = fileNames
        context.coordinator.onOpenLink = onOpenLink
        context.coordinator.onTextChange = onTextChange
        if textView.string != text {
            textView.string = text
            context.coordinator.applyLinkStyling(to: textView)
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onOpenLink: (String) -> Void
        var onTextChange: ((String) -> Void)?
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
                value: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
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

// MARK: - ContentView

struct ContentView: View {
    @AppStorage("vaultBookmark") private var vaultBookmarkData: Data = Data()
    @State private var graph = VaultGraph()
    @State private var vaultURL: URL?
    @State private var openFileURL: URL?
    @State private var fileContent: String = ""
    @State private var showQuickOpen: Bool = false
    @State private var searchQuery: String = ""
    @State private var editingTitle: String?
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isTitleFocused: Bool
    @AccessibilityFocusState private var isSearchA11yFocused: Bool

    var filteredFiles: [VaultGraph.FileEntry] {
        graph.search(searchQuery)
    }

    var body: some View {
        ZStack {
            if vaultURL != nil {
                editorView
            } else {
                selectVaultView
            }

            if showQuickOpen {
                quickOpenOverlay
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            restoreVault()
        }
        .focusedSceneValue(\.showQuickOpen, $showQuickOpen)
        .focusedSceneValue(\.saveAction, saveCurrentFile)
        .focusedSceneValue(\.newFileAction, createNewFile)
        .onChange(of: showQuickOpen) { _, newValue in
            if newValue {
                isSearchFocused = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isSearchA11yFocused = true
                }
            }
        }
    }

    private var selectVaultView: some View {
        VStack(spacing: 16) {
            Text("No vault selected")
                .font(.title2)
                .foregroundStyle(.secondary)
            Button("Select Vault Folder") {
                selectVault()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editorView: some View {
        Group {
            if let url = openFileURL {
                VStack(spacing: 0) {
                    noteTitleField(for: url)
                    Divider()
                    MarkdownTextView(
                        text: $fileContent,
                        fileNames: graph.sortedNames,
                        onOpenLink: { openLinkedFile($0) },
                        onTextChange: { newContent in
                            fileContent = newContent
                            if let url = openFileURL {
                                try? newContent.write(to: url, atomically: true, encoding: .utf8)
                            }
                            if let name = openFileURL?.deletingPathExtension().lastPathComponent {
                                graph.updateLinks(for: name, content: newContent)
                            }
                        }
                    )
                }
            } else {
                Text("Press ⌘O to open a file")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func noteTitleField(for url: URL) -> some View {
        let name = url.deletingPathExtension().lastPathComponent
        return TextField("Note title", text: Binding(
            get: { editingTitle ?? name },
            set: { editingTitle = $0 }
        ))
        .textFieldStyle(.plain)
        .font(.title)
        .fontWeight(.bold)
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .focused($isTitleFocused)
        .onAppear { editingTitle = nil }
        .onSubmit { renameCurrentFile() }
        .onChange(of: openFileURL) { editingTitle = nil }
    }

    private var quickOpenOverlay: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                TextField("Search files...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .padding(12)
                    .focused($isSearchFocused)
                    .accessibilityFocused($isSearchA11yFocused)
                    .accessibilityLabel("Search files")
                    .onSubmit {
                        if let first = filteredFiles.first {
                            openFile(first.url)
                        }
                    }

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredFiles, id: \.name) { file in
                            Button {
                                openFile(file.url)
                            } label: {
                                Text(file.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 20)
            .frame(width: 500)
            .padding(.top, 50)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.3))
        .onTapGesture {
            closeQuickOpen()
        }
        .onExitCommand {
            closeQuickOpen()
        }
    }

    private func selectVault() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select your vault folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Use URL directly from NSOpenPanel — it carries sandbox access
        vaultURL = url
        graph.build(from: url)

        // Try to persist access for next launch via bookmark
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
            vaultBookmarkData = bookmark
        } else if let bookmark = try? url.bookmarkData() {
            vaultBookmarkData = bookmark
        }
    }

    private func restoreVault() {
        guard !vaultBookmarkData.isEmpty else { return }

        // Try security-scoped bookmark first
        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: vaultBookmarkData,
            options: .withSecurityScope,
            bookmarkDataIsStale: &isStale
        ), url.startAccessingSecurityScopedResource() {
            vaultURL = url
            graph.build(from: url)
            if isStale {
                if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
                    vaultBookmarkData = bookmark
                }
            }
            return
        }

        // Fall back to non-scoped bookmark — will need re-select if sandboxed
        if let url = try? URL(
            resolvingBookmarkData: vaultBookmarkData,
            bookmarkDataIsStale: &isStale
        ), FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false)) {
            vaultURL = url
            graph.build(from: url)
            return
        }

        // Bookmark is dead — clear it so user sees vault picker
        vaultBookmarkData = Data()
    }

    private func openFile(_ url: URL) {
        do {
            fileContent = try String(contentsOf: url, encoding: .utf8)
            openFileURL = url
        } catch {}
        closeQuickOpen()
    }

    private func openLinkedFile(_ name: String) {
        if let url = graph.url(for: name) {
            openFile(url)
        }
    }

    private func closeQuickOpen() {
        showQuickOpen = false
        searchQuery = ""
    }

    private func saveCurrentFile() {
        guard let url = openFileURL else { return }
        try? fileContent.write(to: url, atomically: true, encoding: .utf8)
    }

    private func createNewFile() {
        guard let vault = vaultURL else { return }
        let fm = FileManager.default
        let name = "Untitled"
        var url = vault.appendingPathComponent("\(name).md")
        var counter = 1
        while fm.fileExists(atPath: url.path(percentEncoded: false)) {
            url = vault.appendingPathComponent("\(name) \(counter).md")
            counter += 1
        }
        do {
            try Data().write(to: url)
        } catch {
            return
        }
        let actualName = url.deletingPathExtension().lastPathComponent
        graph.addFile(name: actualName, url: url)
        fileContent = ""
        openFileURL = url
        editingTitle = actualName
        isTitleFocused = true
    }

    private func renameCurrentFile() {
        guard let oldURL = openFileURL,
              let newTitle = editingTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !newTitle.isEmpty else {
            editingTitle = nil
            return
        }

        let oldName = oldURL.deletingPathExtension().lastPathComponent
        guard newTitle != oldName else {
            editingTitle = nil
            return
        }

        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent("\(newTitle).md")
        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
            openFileURL = newURL
            graph.rename(from: oldName, to: newTitle, newURL: newURL)
            editingTitle = nil
        } catch {}
    }
}

#Preview {
    ContentView()
}
