import AppKit
import Foundation

@Observable
class AppState {
    var graph = VaultGraph()
    var vaultURL: URL?
    private var hasRestored = false

    var fontSize: CGFloat = UserDefaults.standard.object(forKey: "fontSize") as? CGFloat ?? 14 {
        didSet { UserDefaults.standard.set(fontSize, forKey: "fontSize") }
    }

    var wordWrap: Bool = UserDefaults.standard.object(forKey: "wordWrap") as? Bool ?? true {
        didSet { UserDefaults.standard.set(wordWrap, forKey: "wordWrap") }
    }

    var autoSave: Bool = UserDefaults.standard.object(forKey: "autoSave") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoSave, forKey: "autoSave") }
    }

    var dynamicRendering: Bool = UserDefaults.standard.object(forKey: "dynamicRendering") as? Bool ?? true {
        didSet { UserDefaults.standard.set(dynamicRendering, forKey: "dynamicRendering") }
    }

    func restoreVaultIfNeeded() {
        guard !hasRestored else { return }
        hasRestored = true

        guard let bookmarkData = UserDefaults.standard.data(forKey: "vaultBookmark"),
              !bookmarkData.isEmpty else { return }

        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            bookmarkDataIsStale: &isStale
        ), url.startAccessingSecurityScopedResource() {
            vaultURL = url
            graph.build(from: url)
            if isStale { saveBookmark(for: url) }
            return
        }

        if let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            bookmarkDataIsStale: &isStale
        ), FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false)) {
            vaultURL = url
            graph.build(from: url)
            return
        }

        UserDefaults.standard.removeObject(forKey: "vaultBookmark")
    }

    func setVault(_ url: URL) {
        vaultURL = url
        graph.build(from: url)
        saveBookmark(for: url)
    }

    func clearVault() {
        vaultURL?.stopAccessingSecurityScopedResource()
        vaultURL = nil
        graph = VaultGraph()
        UserDefaults.standard.removeObject(forKey: "vaultBookmark")
    }

    func createNewVault() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.title = "Create New Vault"
        panel.nameFieldLabel = "Vault Name:"
        panel.nameFieldStringValue = "My Vault"
        panel.prompt = "Create"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            return
        }

        let welcomeURL = url.appendingPathComponent("Welcome.md")
        let welcomeContent = """
        # Welcome to Monatic

        A simple markdown editor.

        ## Keyboard Shortcuts

        - Cmd+N — New Note
        - Cmd+O — Quick Open
        - Cmd+S — Save
        - Cmd+F — Find
        """

        try? welcomeContent.write(to: welcomeURL, atomically: true, encoding: .utf8)

        vaultURL = url
        graph.build(from: url)
        saveBookmark(for: url)
    }

    private func saveBookmark(for url: URL) {
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
            UserDefaults.standard.set(bookmark, forKey: "vaultBookmark")
        } else if let bookmark = try? url.bookmarkData() {
            UserDefaults.standard.set(bookmark, forKey: "vaultBookmark")
        }
    }
}
