import SwiftUI

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var onOpenLink: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onOpenLink: onOpenLink)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
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
        context.coordinator.applyLinkStyling(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
            context.coordinator.applyLinkStyling(to: textView)
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onOpenLink: (String) -> Void
        private var isUpdating = false

        init(text: Binding<String>, onOpenLink: @escaping (String) -> Void) {
            self.text = text
            self.onOpenLink = onOpenLink
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            isUpdating = true
            text.wrappedValue = textView.string
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

struct ContentView: View {
    @AppStorage("vaultBookmark") private var vaultBookmarkData: Data = Data()
    @State private var vaultURL: URL?
    @State private var openFileURL: URL?
    @State private var fileContent: String = ""
    @State private var showQuickOpen: Bool = false
    @State private var searchQuery: String = ""
    @State private var markdownFiles: [URL] = []
    @FocusState private var isSearchFocused: Bool

    var filteredFiles: [URL] {
        if searchQuery.isEmpty {
            return markdownFiles
        }
        return markdownFiles.filter {
            $0.lastPathComponent.localizedCaseInsensitiveContains(searchQuery)
        }
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
        .onChange(of: showQuickOpen) { _, newValue in
            if newValue {
                loadMarkdownFiles()
                isSearchFocused = true
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
            if openFileURL != nil {
                MarkdownTextView(text: $fileContent) { linkName in
                    openLinkedFile(linkName)
                }
                .onChange(of: fileContent) {
                    saveCurrentFile()
                }
            } else {
                Text("Press ⌘O to open a file")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var quickOpenOverlay: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                TextField("Search files...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .padding(12)
                    .focused($isSearchFocused)
                    .onSubmit {
                        if let first = filteredFiles.first {
                            openFile(first)
                        }
                    }

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredFiles, id: \.self) { file in
                            Button {
                                openFile(file)
                            } label: {
                                Text(file.lastPathComponent)
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

        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope)
            vaultBookmarkData = bookmark
            vaultURL = url
            loadMarkdownFiles()
        } catch {}
    }

    private func restoreVault() {
        guard !vaultBookmarkData.isEmpty else { return }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: vaultBookmarkData,
                options: .withSecurityScope,
                bookmarkDataIsStale: &isStale
            )
            guard url.startAccessingSecurityScopedResource() else { return }
            vaultURL = url
            loadMarkdownFiles()
            if isStale {
                vaultBookmarkData = try url.bookmarkData(options: .withSecurityScope)
            }
        } catch {}
    }

    private func loadMarkdownFiles() {
        guard let vault = vaultURL else { return }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: vault,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var files: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension == "md" {
                files.append(url)
            }
        }
        markdownFiles = files.sorted { $0.lastPathComponent.localizedCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func openFile(_ url: URL) {
        do {
            fileContent = try String(contentsOf: url, encoding: .utf8)
            openFileURL = url
        } catch {}
        closeQuickOpen()
    }

    private func openLinkedFile(_ name: String) {
        if let target = markdownFiles.first(where: { $0.deletingPathExtension().lastPathComponent == name }) {
            openFile(target)
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
}

#Preview {
    ContentView()
}
