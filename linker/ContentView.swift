import Observation
import SwiftUI
import UniformTypeIdentifiers

@Observable
class NavigationHistory {
    struct Entry {
        let url: URL
        var cursorPosition: Int
    }

    private var stack: [Entry] = []
    private var currentIndex: Int = -1
    @ObservationIgnored var latestCursorPosition: Int = 0

    var canGoBack: Bool { currentIndex > 0 }
    var canGoForward: Bool { currentIndex < stack.count - 1 }

    func visit(_ url: URL) {
        if currentIndex >= 0, currentIndex < stack.count, stack[currentIndex].url == url { return }
        stack.removeSubrange((currentIndex + 1)...)
        stack.append(Entry(url: url, cursorPosition: 0))
        currentIndex = stack.count - 1
    }

    func saveCursorPosition(_ position: Int) {
        guard currentIndex >= 0, currentIndex < stack.count else { return }
        stack[currentIndex].cursorPosition = position
    }

    func goBack() -> Entry? {
        guard canGoBack else { return nil }
        currentIndex -= 1
        return stack[currentIndex]
    }

    func goForward() -> Entry? {
        guard canGoForward else { return nil }
        currentIndex += 1
        return stack[currentIndex]
    }
}

@Observable
class EditorTab: Identifiable {
    let id = UUID()
    var openFileURL: URL?
    var fileContent: String = ""
    var history = NavigationHistory()
    var cursorPositionToRestore: Int?
    var showReferences: Bool = false

    var title: String {
        openFileURL?.deletingPathExtension().lastPathComponent ?? "Empty"
    }
}

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
                            filename: tab.title,
                            graph: appState.graph,
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
                    appState.graph.indexFile(name: name, url: url)
                }
            }
        )
    }
}

// MARK: - References Panel

struct ReferencesPanel: View {
    let filename: String
    let graph: VaultGraph
    var onOpenFile: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                referenceSection(
                    title: "Outgoing",
                    items: graph.outgoingReferences(for: filename).map { ref in
                        ReferenceItem(name: ref.filename, line: ref.line, column: ref.column, exists: graph.fileNameSet.contains(ref.filename))
                    }
                )

                referenceSection(
                    title: "Incoming",
                    items: graph.incomingReferences(for: filename).map { item in
                        ReferenceItem(name: item.source, line: item.reference.line, column: item.reference.column, exists: true)
                    }
                )

                Spacer()
            }
            .padding(12)
        }
    }

    private struct ReferenceItem {
        let name: String
        let line: Int
        let column: Int
        let exists: Bool
    }

    @ViewBuilder
    private func referenceSection(title: String, items: [ReferenceItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if items.isEmpty {
                Text("None")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Button {
                        onOpenFile(item.name)
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(item.name)
                                .font(.system(size: 12))
                                .foregroundStyle(item.exists ? .primary : .secondary)
                            Spacer()
                            Text("\(item.line):\(item.column)")
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
