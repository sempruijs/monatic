import AppKit
import Foundation

@Observable
class AppState {
    var graph = VaultGraph()
    var vaultURL: URL?
    var fontSize: CGFloat = UserDefaults.standard.object(forKey: "fontSize") as? CGFloat ?? 14
    var wordWrap: Bool = UserDefaults.standard.object(forKey: "wordWrap") as? Bool ?? true
    var templatesFolderURL: URL?
    var newTabShouldQuickOpen = false
    private var hasRestored = false
    private var hasRestoredTemplates = false

    func increaseFontSize() {
        fontSize = min(fontSize + 1, 48)
        UserDefaults.standard.set(fontSize, forKey: "fontSize")
    }

    func decreaseFontSize() {
        fontSize = max(fontSize - 1, 8)
        UserDefaults.standard.set(fontSize, forKey: "fontSize")
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
            if isStale {
                if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
                    UserDefaults.standard.set(bookmark, forKey: "vaultBookmark")
                }
            }
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

        let fm = FileManager.default
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            return
        }

        let welcomeURL = url.appendingPathComponent("Welcome.md")
        let welcomeContent = """
        # Welcome to Monatic

        Monatic is a markdown editor built around **[[wiki-style links]]**.

        ## Formatting

        You can use all common markdown formatting:

        - **Bold** with `**double asterisks**`
        - *Italic* with `*single asterisks*`
        - Headings with `#` through `#####`

        ## Links

        Link to other notes by wrapping their name in double brackets: `[[Note Name]]`.
        If the note doesn't exist yet, clicking the link will create it.

        ## Keyboard Shortcuts

        - Cmd+N - New Note
        - Cmd+O - Quick Open
        - Cmd+T - New Tab
        - Cmd+F - Find
        - Cmd+S - Save
        - Cmd+Shift+L - Toggle Links Sidebar
        - Cmd+Shift+T - Insert Template
        - Cmd+Shift+Delete - Delete Current File

        ## Deleting Files

        To delete a file, press **Cmd+Shift+Delete**. You will be asked to confirm before the file is moved to the Trash.

        ## Learn More

        Visit [monatic.pruijs.net](https://monatic.pruijs.net) for more information.
        """

        try? welcomeContent.write(to: welcomeURL, atomically: true, encoding: .utf8)

        vaultURL = url
        graph.build(from: url)

        if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
            UserDefaults.standard.set(bookmark, forKey: "vaultBookmark")
        } else if let bookmark = try? url.bookmarkData() {
            UserDefaults.standard.set(bookmark, forKey: "vaultBookmark")
        }
    }

    func selectVault() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select your vault folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        vaultURL = url
        graph.build(from: url)

        if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
            UserDefaults.standard.set(bookmark, forKey: "vaultBookmark")
        } else if let bookmark = try? url.bookmarkData() {
            UserDefaults.standard.set(bookmark, forKey: "vaultBookmark")
        }
    }

    func restoreTemplatesFolderIfNeeded() {
        guard !hasRestoredTemplates else { return }
        hasRestoredTemplates = true

        guard let bookmarkData = UserDefaults.standard.data(forKey: "templatesFolderBookmark"),
              !bookmarkData.isEmpty else { return }

        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            bookmarkDataIsStale: &isStale
        ), url.startAccessingSecurityScopedResource() {
            templatesFolderURL = url
            if isStale {
                if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
                    UserDefaults.standard.set(bookmark, forKey: "templatesFolderBookmark")
                }
            }
            return
        }

        if let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            bookmarkDataIsStale: &isStale
        ), FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false)) {
            templatesFolderURL = url
            return
        }

        UserDefaults.standard.removeObject(forKey: "templatesFolderBookmark")
    }

    func selectTemplatesFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select your templates folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        templatesFolderURL = url

        if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
            UserDefaults.standard.set(bookmark, forKey: "templatesFolderBookmark")
        } else if let bookmark = try? url.bookmarkData() {
            UserDefaults.standard.set(bookmark, forKey: "templatesFolderBookmark")
        }
    }

    func templateFiles() -> [(name: String, url: URL)] {
        guard let folder = templatesFolderURL else { return [] }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [(name: String, url: URL)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "md" else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            results.append((name: name, url: url))
        }
        return results.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
}
