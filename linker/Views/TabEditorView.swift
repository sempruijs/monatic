import SwiftUI

struct TabEditorView: View {
    @Bindable var tab: EditorTab
    let appState: AppState
    var onOpenLink: (String) -> Void
    @State private var editingName: String = ""
    @State private var nameError: String?

    private static let invalidCharacters = CharacterSet(charactersIn: ":/\\")

    var body: some View {
        VStack(spacing: 0) {
            switch tab.contentType {
            case .markdown:
                markdownEditor
            case .pdf:
                if let url = tab.openFileURL {
                    PDFViewer(url: url)
                }
            case .image:
                if let url = tab.openFileURL {
                    ImageViewer(url: url)
                }
            case .audio:
                if let url = tab.openFileURL {
                    AudioPlayer(url: url)
                }
            case .unsupported:
                Text("Unsupported file type")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var markdownEditor: some View {
        MarkdownTextView(
            text: $tab.fileContent,
            fileNames: appState.graph.fileNameSet,
            fontSize: appState.fontSize,
            wordWrap: appState.wordWrap,
            dynamicRendering: appState.dynamicRendering,
            cursorPositionToRestore: $tab.cursorPositionToRestore,
            needsFocus: $tab.needsFocus,
            pendingInsert: $tab.pendingInsert,
            onOpenLink: onOpenLink,
            onCursorChange: { tab.history.latestCursorPosition = $0 },
            onTextChange: { newContent in
                tab.fileContent = newContent
                if appState.autoSave, let url = tab.openFileURL {
                    try? newContent.write(to: url, atomically: true, encoding: .utf8)
                    let name = url.deletingPathExtension().lastPathComponent
                    tab.scheduleIndex(name: name, url: url, graph: appState.graph)
                }
            },
            titleText: $editingName,
            titleError: nameError,
            onTitleCommit: {
                renameFile()
                if nameError == nil {
                    tab.needsFocus = true
                }
            },
            onTitleFocusLost: {
                renameFile()
                if nameError != nil { syncName() }
                nameError = nil
            },
            needsTitleFocus: $tab.needsNameFieldFocus
        )
        .onAppear { syncName() }
        .onChange(of: tab.openFileURL) { _, _ in syncName() }
        .onChange(of: editingName) { _, newValue in
            validateName(newValue)
        }
    }

    private func syncName() {
        editingName = tab.openFileURL?.deletingPathExtension().lastPathComponent ?? ""
    }

    private func validateName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = tab.openFileURL else {
            nameError = nil
            return
        }
        let currentName = url.deletingPathExtension().lastPathComponent
        if trimmed.isEmpty || trimmed == currentName {
            nameError = nil
            return
        }
        if trimmed.unicodeScalars.contains(where: { Self.invalidCharacters.contains($0) }) {
            nameError = "Filename cannot contain : / or \\"
            return
        }
        let ext = url.pathExtension
        let newURL = url.deletingLastPathComponent().appendingPathComponent("\(trimmed).\(ext)")
        if FileManager.default.fileExists(atPath: newURL.path(percentEncoded: false)) {
            nameError = "A file named \"\(trimmed)\" already exists"
            return
        }
        nameError = nil
    }

    private func renameFile() {
        guard let url = tab.openFileURL else { return }
        let currentName = url.deletingPathExtension().lastPathComponent
        let newName = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != currentName else {
            editingName = currentName
            return
        }

        validateName(editingName)
        if nameError != nil { return }

        let ext = url.pathExtension
        let newURL = url.deletingLastPathComponent().appendingPathComponent("\(newName).\(ext)")

        let incoming = appState.graph.incomingReferences(for: currentName)
        if incoming.isEmpty {
            performRename(oldName: currentName, newName: newName, oldURL: url, newURL: newURL, updateReferences: false)
            return
        }

        switch appState.renameReferenceBehavior {
        case .ask:
            let shouldUpdate = showRenameReferencesAlert(oldName: currentName, newName: newName, count: incoming.count)
            performRename(oldName: currentName, newName: newName, oldURL: url, newURL: newURL, updateReferences: shouldUpdate)
        case .update:
            performRename(oldName: currentName, newName: newName, oldURL: url, newURL: newURL, updateReferences: true)
        case .dontUpdate:
            performRename(oldName: currentName, newName: newName, oldURL: url, newURL: newURL, updateReferences: false)
        }
    }

    private func showRenameReferencesAlert(oldName: String, newName: String, count: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Update References"
        alert.informativeText = "\(count) file(s) reference \"\(oldName)\". Update them to \"\(newName)\"?"
        alert.addButton(withTitle: "Update (\(count))")
        alert.addButton(withTitle: "Don't Update")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"

        let response = alert.runModal()
        let shouldUpdate = response == .alertFirstButtonReturn

        if alert.suppressionButton?.state == .on {
            appState.renameReferenceBehavior = shouldUpdate ? .update : .dontUpdate
        }

        return shouldUpdate
    }

    private func performRename(oldName: String, newName: String, oldURL: URL, newURL: URL, updateReferences: Bool) {
        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
        } catch {
            editingName = oldName
            return
        }
        if updateReferences {
            appState.graph.updateReferencesInFiles(oldName: oldName, newName: newName)
        }
        appState.graph.renameFile(oldName: oldName, newName: newName, newURL: newURL)
        tab.openFileURL = newURL
    }
}
