import SwiftUI

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.tabbingMode = .preferred

            if let existing = NSApp.windows.first(where: {
                $0 !== window &&
                $0.isVisible &&
                $0.tabbingIdentifier == window.tabbingIdentifier &&
                $0.tabGroup !== window.tabGroup
            }) {
                existing.addTabbedWindow(window, ordered: .above)
                window.makeKeyAndOrderFront(nil)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if !(window.tabGroup?.isTabBarVisible ?? false) {
                    window.toggleTabBar(nil)
                }
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

@Observable
class NavigationHistory {
    private var stack: [URL] = []
    private var currentIndex: Int = -1

    var canGoBack: Bool { currentIndex > 0 }
    var canGoForward: Bool { currentIndex < stack.count - 1 }

    func visit(_ url: URL) {
        if currentIndex >= 0, currentIndex < stack.count, stack[currentIndex] == url { return }
        stack.removeSubrange((currentIndex + 1)...)
        stack.append(url)
        currentIndex = stack.count - 1
    }

    func goBack() -> URL? {
        guard canGoBack else { return nil }
        currentIndex -= 1
        return stack[currentIndex]
    }

    func goForward() -> URL? {
        guard canGoForward else { return nil }
        currentIndex += 1
        return stack[currentIndex]
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @State private var openFileURL: URL?
    @State private var fileContent: String = ""
    @State private var showQuickOpen: Bool = false
    @State private var editingTitle: String?
    @State private var focusTitleField: Bool = false
    @State private var showLinks: Bool = false
    @State private var showFindBar: Bool = false
    @State private var showTemplatePicker: Bool = false
    @State private var textToInsert: String?
    @State private var history = NavigationHistory()
    @State private var showDeleteConfirmation: Bool = false

    private var currentNoteName: String? {
        openFileURL?.deletingPathExtension().lastPathComponent
    }

    var body: some View {
        mainContent
            .focusedSceneValue(\.closeOtherTabsAction) { closeOtherTabs() }
            .focusedSceneValue(\.toggleLinksAction) { withAnimation { showLinks.toggle() } }
            .focusedSceneValue(\.deleteFileAction, openFileURL != nil ? { showDeleteConfirmation = true } : nil)
            .alert("Delete File", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) { deleteCurrentFile() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete \"\(currentNoteName ?? "this file")\"? This cannot be undone.")
            }
    }

    private var mainContent: some View {
        ZStack {
            if appState.vaultURL != nil {
                editorView
            } else {
                selectVaultView
            }

            if showQuickOpen {
                QuickOpenPanel(isPresented: $showQuickOpen, onOpenFile: openFile)
            }

            if showTemplatePicker {
                TemplatePicker(isPresented: $showTemplatePicker, noteName: currentNoteName ?? "") { processed in
                    textToInsert = processed
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            appState.restoreVaultIfNeeded()
            appState.restoreTemplatesFolderIfNeeded()
            if appState.vaultURL != nil && openFileURL == nil {
                showQuickOpen = true
            }
        }
        .navigationTitle(currentNoteName ?? "linker")
        .background(WindowConfigurator())
        .focusedSceneValue(\.showQuickOpen, $showQuickOpen)
        .focusedSceneValue(\.saveAction, saveCurrentFile)
        .focusedSceneValue(\.newFileAction, createNewFile)
        .focusedSceneValue(\.newTabAction) { openWindow(id: "editor") }
        .focusedSceneValue(\.goBackAction, history.canGoBack ? { goBack() } : nil)
        .focusedSceneValue(\.goForwardAction, history.canGoForward ? { goForward() } : nil)
        .focusedSceneValue(\.findAction) { showFindBar = true }
        .focusedSceneValue(\.showTemplatePicker, $showTemplatePicker)
        .focusedSceneValue(\.increaseFontAction) { appState.increaseFontSize() }
        .focusedSceneValue(\.decreaseFontAction) { appState.decreaseFontSize() }
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
            if openFileURL != nil {
                HStack(spacing: 0) {
                    MarkdownTextView(
                        text: $fileContent,
                        fileNames: appState.graph.sortedNames,
                        fontSize: appState.fontSize,
                        wordWrap: appState.wordWrap,
                        showFindBar: $showFindBar,
                        textToInsert: $textToInsert,
                        noteName: currentNoteName ?? "",
                        editingTitle: $editingTitle,
                        onTitleSubmit: { renameCurrentFile() },
                        focusTitle: $focusTitleField,
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

                    if showLinks {
                        Divider()
                        linksSidebar
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button(action: goBack) {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .disabled(!history.canGoBack)
                    }
                    ToolbarItem(placement: .navigation) {
                        Button(action: goForward) {
                            Label("Forward", systemImage: "chevron.right")
                        }
                        .disabled(!history.canGoForward)
                    }
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

    // MARK: - Actions

    private func openFile(_ url: URL) {
        do {
            fileContent = try String(contentsOf: url, encoding: .utf8)
            openFileURL = url
            editingTitle = nil
            history.visit(url)
        } catch {}
        showQuickOpen = false
    }

    private func goBack() {
        guard let url = history.goBack() else { return }
        do {
            fileContent = try String(contentsOf: url, encoding: .utf8)
            openFileURL = url
        } catch {}
    }

    private func goForward() {
        guard let url = history.goForward() else { return }
        do {
            fileContent = try String(contentsOf: url, encoding: .utf8)
            openFileURL = url
        } catch {}
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
        focusTitleField = true
    }

    private func closeOtherTabs() {
        guard let currentWindow = NSApp.keyWindow else { return }
        for window in NSApp.windows where window !== currentWindow && window.tabbingIdentifier == currentWindow.tabbingIdentifier && window.isVisible {
            window.performClose(nil)
        }
    }

    private func deleteCurrentFile() {
        guard let url = openFileURL else { return }
        let name = url.deletingPathExtension().lastPathComponent
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            appState.graph.removeFile(name: name)
            openFileURL = nil
            fileContent = ""
        } catch {}
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
