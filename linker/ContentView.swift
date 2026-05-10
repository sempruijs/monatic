import SwiftUI

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
    @State private var showLinks: Bool = false

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

    private var currentNoteName: String? {
        openFileURL?.deletingPathExtension().lastPathComponent
    }

    private var editorView: some View {
        Group {
            if let url = openFileURL {
                HStack(spacing: 0) {
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
                                if let name = currentNoteName {
                                    graph.updateLinks(for: name, content: newContent)
                                }
                            }
                        )
                    }

                    if showLinks {
                        Divider()
                        linksSidebar
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            withAnimation { showLinks.toggle() }
                        } label: {
                            Label("Links", systemImage: "link")
                        }
                    }
                }
            } else {
                Text("Press ⌘O to open a file")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var linksSidebar: some View {
        let name = currentNoteName ?? ""
        let outgoing = graph.outgoing(from: name).sorted()
        let incoming = graph.incoming(to: name).sorted()

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                linkSection(title: "Outgoing", links: outgoing)
                linkSection(title: "Incoming", links: incoming)
            }
            .padding()
        }
        .frame(width: 220)
    }

    private func linkSection(title: String, links: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            if links.isEmpty {
                Text("None")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(links, id: \.self) { link in
                    Button {
                        openLinkedFile(link)
                    } label: {
                        Text(link)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
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

        vaultURL = url
        graph.build(from: url)

        if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
            vaultBookmarkData = bookmark
        } else if let bookmark = try? url.bookmarkData() {
            vaultBookmarkData = bookmark
        }
    }

    private func restoreVault() {
        guard !vaultBookmarkData.isEmpty else { return }

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

        if let url = try? URL(
            resolvingBookmarkData: vaultBookmarkData,
            bookmarkDataIsStale: &isStale
        ), FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false)) {
            vaultURL = url
            graph.build(from: url)
            return
        }

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
