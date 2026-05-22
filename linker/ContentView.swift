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

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var openFileURL: URL?
    @State private var fileContent: String = ""
    @State private var showQuickOpen: Bool = false
    @State private var showVaultPicker: Bool = false
    @State private var history = NavigationHistory()
    @State private var cursorPositionToRestore: Int?
    @State private var showReferences: Bool = false

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
                QuickOpenPanel(isPresented: $showQuickOpen, onOpenFile: openFile)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            appState.restoreVaultIfNeeded()
            if appState.vaultURL != nil && openFileURL == nil {
                if let first = appState.graph.files.first {
                    openFile(first.url)
                }
            }
        }
        .navigationTitle(currentNoteName ?? "Monatic")
        .focusedSceneValue(\.showQuickOpen, $showQuickOpen)
        .focusedSceneValue(\.saveAction, saveCurrentFile)
        .focusedSceneValue(\.newFileAction, createNewFile)
        .focusedSceneValue(\.goBackAction, history.canGoBack ? { goBack() } : nil)
        .focusedSceneValue(\.goForwardAction, history.canGoForward ? { goForward() } : nil)
    }

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
            if openFileURL != nil {
                HStack(spacing: 0) {
                    MarkdownTextView(
                        text: $fileContent,
                        fileNames: appState.graph.fileNameSet,
                        fontSize: appState.fontSize,
                        wordWrap: appState.wordWrap,
                        cursorPositionToRestore: $cursorPositionToRestore,
                        onOpenLink: { openLinkedFile($0) },
                        onCursorChange: { history.latestCursorPosition = $0 },
                        onTextChange: { newContent in
                            fileContent = newContent
                            if appState.autoSave, let url = openFileURL {
                                try? newContent.write(to: url, atomically: true, encoding: .utf8)
                                if let name = currentNoteName {
                                    appState.graph.indexFile(name: name, url: url)
                                }
                            }
                        }
                    )

                    if showReferences, let name = currentNoteName {
                        Divider()
                        ReferencesPanel(
                            filename: name,
                            graph: appState.graph,
                            onOpenFile: { openLinkedFile($0) }
                        )
                        .frame(width: 250)
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        Button(action: goBack) {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .disabled(!history.canGoBack)

                        Button(action: goForward) {
                            Label("Forward", systemImage: "chevron.right")
                        }
                        .disabled(!history.canGoForward)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showReferences.toggle()
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
        history.saveCursorPosition(history.latestCursorPosition)
        do {
            fileContent = try String(contentsOf: url, encoding: .utf8)
            openFileURL = url
            history.visit(url)
        } catch {}
        showQuickOpen = false
    }

    private func goBack() {
        history.saveCursorPosition(history.latestCursorPosition)
        guard let entry = history.goBack() else { return }
        do {
            fileContent = try String(contentsOf: entry.url, encoding: .utf8)
            openFileURL = entry.url
            cursorPositionToRestore = entry.cursorPosition
        } catch {}
    }

    private func goForward() {
        history.saveCursorPosition(history.latestCursorPosition)
        guard let entry = history.goForward() else { return }
        do {
            fileContent = try String(contentsOf: entry.url, encoding: .utf8)
            openFileURL = entry.url
            cursorPositionToRestore = entry.cursorPosition
        } catch {}
    }

    private func saveCurrentFile() {
        guard let url = openFileURL else { return }
        try? fileContent.write(to: url, atomically: true, encoding: .utf8)
        if let name = currentNoteName {
            appState.graph.indexFile(name: name, url: url)
        }
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
        fileContent = ""
        openFileURL = url
    }
}

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
