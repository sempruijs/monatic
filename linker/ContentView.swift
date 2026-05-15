import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var openFileURL: URL?
    @State private var fileContent: String = ""
    @State private var showQuickOpen: Bool = false
    @State private var showVaultPicker: Bool = false

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
                MarkdownTextView(
                    text: $fileContent,
                    fontSize: appState.fontSize,
                    wordWrap: appState.wordWrap,
                    onTextChange: { newContent in
                        fileContent = newContent
                        if appState.autoSave, let url = openFileURL {
                            try? newContent.write(to: url, atomically: true, encoding: .utf8)
                        }
                    }
                )
            } else {
                Text("Press \u{2318}O to open a file")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func openFile(_ url: URL) {
        do {
            fileContent = try String(contentsOf: url, encoding: .utf8)
            openFileURL = url
        } catch {}
        showQuickOpen = false
    }

    private func saveCurrentFile() {
        guard let url = openFileURL else { return }
        try? fileContent.write(to: url, atomically: true, encoding: .utf8)
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

#Preview {
    ContentView()
        .environment(AppState())
}
