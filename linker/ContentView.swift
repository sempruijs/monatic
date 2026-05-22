import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var tabs: [EditorTab] = [EditorTab()]
    @State private var selectedTabID: UUID?
    @State private var showQuickOpen: Bool = false
    @State private var showVaultPicker: Bool = false

    private var selectedTab: EditorTab? {
        tabs.first { $0.id == selectedTabID } ?? tabs.first
    }

    private var currentNoteName: String? {
        selectedTab?.openFileURL?.deletingPathExtension().lastPathComponent
    }

    private var goBackActionBinding: (() -> Void)? {
        selectedTab?.history.canGoBack == true ? { goBack() } : nil
    }

    private var goForwardActionBinding: (() -> Void)? {
        selectedTab?.history.canGoForward == true ? { goForward() } : nil
    }

    private var closeTabActionBinding: (() -> Void)? {
        tabs.count > 1 ? { closeCurrentTab() } : nil
    }

    var body: some View {
        mainContent
            .frame(minWidth: 600, minHeight: 400)
            .onAppear(perform: handleAppear)
            .navigationTitle(currentNoteName ?? "Monatic")
            .focusedSceneValue(\.showQuickOpen, $showQuickOpen)
            .focusedSceneValue(\.saveAction, saveCurrentFile)
            .focusedSceneValue(\.newFileAction, createNewFile)
            .focusedSceneValue(\.newTabAction, addNewTab)
            .focusedSceneValue(\.closeTabAction, closeTabActionBinding)
            .focusedSceneValue(\.goBackAction, goBackActionBinding)
            .focusedSceneValue(\.goForwardAction, goForwardActionBinding)
    }

    private var mainContent: some View {
        ZStack {
            if appState.vaultURL != nil {
                VStack(spacing: 0) {
                    if tabs.count > 1 {
                        tabBar
                    }
                    editorView
                }
            } else {
                selectVaultView
            }

            if showQuickOpen {
                QuickOpenPanel(isPresented: $showQuickOpen, onOpenFile: openFile)
            }
        }
    }

    private func handleAppear() {
        appState.restoreVaultIfNeeded()
        if selectedTabID == nil {
            selectedTabID = tabs.first?.id
        }
        if appState.vaultURL != nil, selectedTab?.openFileURL == nil {
            if let first = appState.graph.files.first {
                openFile(first.url)
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    tabButton(for: tab)
                }
            }
        }
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func tabButton(for tab: EditorTab) -> some View {
        let isSelected = tab.id == selectedTabID
        return HStack(spacing: 6) {
            Text(tab.title)
                .font(.system(size: 11))
                .lineLimit(1)
            if tabs.count > 1 {
                Button {
                    closeTab(tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedTabID = tab.id
        }
    }

    // MARK: - Views

    private var selectVaultView: some View {
        VStack(spacing: 16) {
            Text("No vault selected")
                .font(.title2)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Open Existing Vault") {
                    showVaultPicker = true
                }
                Button("Create New Vault") {
                    appState.createNewVault()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(isPresented: $showVaultPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                _ = url.startAccessingSecurityScopedResource()
                appState.setVault(url)
            }
        }
    }

    private var editorView: some View {
        Group {
            if let tab = selectedTab, tab.openFileURL != nil {
                HStack(spacing: 0) {
                    TabEditorView(tab: tab, appState: appState, onOpenLink: openLinkedFile)

                    if tab.showReferences, tab.openFileURL != nil {
                        Divider()
                        ReferencesPanel(
                            outgoing: outgoingItems(for: tab.title),
                            incoming: incomingItems(for: tab.title),
                            onOpenFile: { openLinkedFile($0) }
                        )
                        .frame(width: 250)
                    }
                }
                .id(tab.id)
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        Button(action: goBack) {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .disabled(tab.history.canGoBack != true)

                        Button(action: goForward) {
                            Label("Forward", systemImage: "chevron.right")
                        }
                        .disabled(tab.history.canGoForward != true)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            tab.showReferences.toggle()
                        } label: {
                            Label("References", systemImage: "link")
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

    // MARK: - Tab Management

    private func addNewTab() {
        let tab = EditorTab()
        tabs.append(tab)
        selectedTabID = tab.id
    }

    private func closeCurrentTab() {
        guard let id = selectedTabID, tabs.count > 1 else { return }
        closeTab(id)
    }

    private func closeTab(_ id: UUID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = id == selectedTabID
        tabs.remove(at: index)
        if wasSelected {
            let newIndex = min(index, tabs.count - 1)
            selectedTabID = tabs[newIndex].id
        }
    }

    // MARK: - References

    private func outgoingItems(for filename: String) -> [ReferenceItem] {
        appState.graph.outgoingReferences(for: filename).map {
            ReferenceItem(name: $0.filename, line: $0.line, column: $0.column, exists: appState.graph.fileNameSet.contains($0.filename))
        }
    }

    private func incomingItems(for filename: String) -> [ReferenceItem] {
        appState.graph.incomingReferences(for: filename).map {
            ReferenceItem(name: $0.source, line: $0.reference.line, column: $0.reference.column, exists: true)
        }
    }

    // MARK: - File Actions

    private func openLinkedFile(_ name: String) {
        if let url = appState.graph.url(for: name) {
            openFile(url)
        } else {
            guard let vault = appState.vaultURL else { return }
            let url = vault.appendingPathComponent("\(name).md")
            do {
                try Data().write(to: url)
                appState.graph.addFile(name: name, url: url)
                openFile(url)
            } catch {}
        }
    }

    private func openFile(_ url: URL) {
        guard let tab = selectedTab else { return }
        tab.history.saveCursorPosition(tab.history.latestCursorPosition)
        do {
            tab.fileContent = try String(contentsOf: url, encoding: .utf8)
            tab.openFileURL = url
            tab.history.visit(url)
            appState.graph.recordVisit(url)
        } catch {}
        showQuickOpen = false
    }

    private func goBack() {
        guard let tab = selectedTab else { return }
        tab.history.saveCursorPosition(tab.history.latestCursorPosition)
        guard let entry = tab.history.goBack() else { return }
        do {
            tab.fileContent = try String(contentsOf: entry.url, encoding: .utf8)
            tab.openFileURL = entry.url
            tab.cursorPositionToRestore = entry.cursorPosition
        } catch {}
    }

    private func goForward() {
        guard let tab = selectedTab else { return }
        tab.history.saveCursorPosition(tab.history.latestCursorPosition)
        guard let entry = tab.history.goForward() else { return }
        do {
            tab.fileContent = try String(contentsOf: entry.url, encoding: .utf8)
            tab.openFileURL = entry.url
            tab.cursorPositionToRestore = entry.cursorPosition
        } catch {}
    }

    private func saveCurrentFile() {
        guard let tab = selectedTab, let url = tab.openFileURL else { return }
        try? tab.fileContent.write(to: url, atomically: true, encoding: .utf8)
        let name = url.deletingPathExtension().lastPathComponent
        appState.graph.indexFile(name: name, url: url)
    }

    private func createNewFile() {
        guard let folder = appState.vaultURL else { return }
        let fm = FileManager.default
        let name = "Untitled"
        var url = folder.appendingPathComponent("\(name).md")
        var counter = 1
        while fm.fileExists(atPath: url.path(percentEncoded: false)) {
            url = folder.appendingPathComponent("\(name) \(counter).md")
            counter += 1
        }
        do {
            try Data().write(to: url)
        } catch {
            return
        }
        let actualName = url.deletingPathExtension().lastPathComponent
        appState.graph.addFile(name: actualName, url: url)
        guard let tab = selectedTab else { return }
        tab.fileContent = ""
        tab.openFileURL = url
    }
}

// MARK: - Tab Editor View

struct TabEditorView: View {
    @Bindable var tab: EditorTab
    let appState: AppState
    var onOpenLink: (String) -> Void

    var body: some View {
        MarkdownTextView(
            text: $tab.fileContent,
            fileNames: appState.graph.fileNameSet,
            fontSize: appState.fontSize,
            wordWrap: appState.wordWrap,
            cursorPositionToRestore: $tab.cursorPositionToRestore,
            onOpenLink: onOpenLink,
            onCursorChange: { tab.history.latestCursorPosition = $0 },
            onTextChange: { newContent in
                tab.fileContent = newContent
                if appState.autoSave, let url = tab.openFileURL {
                    try? newContent.write(to: url, atomically: true, encoding: .utf8)
                    let name = url.deletingPathExtension().lastPathComponent
                    tab.scheduleIndex(name: name, url: url, graph: appState.graph)
                }
            }
        )
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
