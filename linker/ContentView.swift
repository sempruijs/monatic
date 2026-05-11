import SwiftUI

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.tabbingMode = .preferred

            // If another editor window exists, join it as a tab
            if let existing = NSApp.windows.first(where: {
                $0 !== window &&
                $0.isVisible &&
                $0.tabbingIdentifier == window.tabbingIdentifier &&
                $0.tabGroup !== window.tabGroup
            }) {
                existing.addTabbedWindow(window, ordered: .above)
                window.makeKeyAndOrderFront(nil)
            }

            // Always show the tab bar
            if !(window.tabGroup?.isTabBarVisible ?? false) {
                window.toggleTabBar(nil)
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
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
        appState.graph.search(searchQuery)
    }

    private var currentNoteName: String? {
        openFileURL?.deletingPathExtension().lastPathComponent
    }

    var body: some View {
        ZStack {
            if appState.vaultURL != nil {
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
            appState.restoreVaultIfNeeded()
        }
        .background(WindowConfigurator())
        .focusedSceneValue(\.showQuickOpen, $showQuickOpen)
        .focusedSceneValue(\.saveAction, saveCurrentFile)
        .focusedSceneValue(\.newFileAction, createNewFile)
        .focusedSceneValue(\.newTabAction) { openWindow(id: "editor") }
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
                appState.selectVault()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            fileNames: appState.graph.sortedNames,
                            onOpenLink: { openLinkedFile($0) },
                            onTextChange: { newContent in
                                fileContent = newContent
                                if let url = openFileURL {
                                    try? newContent.write(to: url, atomically: true, encoding: .utf8)
                                }
                                if let name = currentNoteName {
                                    appState.graph.updateLinks(for: name, content: newContent)
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
                Text("Press \u{2318}O to open a file")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var linksSidebar: some View {
        let name = currentNoteName ?? ""
        let outgoing = appState.graph.outgoing(from: name).sorted()
        let incoming = appState.graph.incoming(to: name).sorted()

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

    // MARK: - Actions

    private func openFile(_ url: URL) {
        do {
            fileContent = try String(contentsOf: url, encoding: .utf8)
            openFileURL = url
        } catch {}
        closeQuickOpen()
    }

    private func openLinkedFile(_ name: String) {
        if let url = appState.graph.url(for: name) {
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
        guard let vault = appState.vaultURL else { return }
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
        appState.graph.addFile(name: actualName, url: url)
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
            appState.graph.rename(from: oldName, to: newTitle, newURL: newURL)
            editingTitle = nil
        } catch {}
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
