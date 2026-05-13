import AppKit
import Foundation

@Observable
class AppState {
    var graph = VaultGraph()
    var vaultURL: URL?
    var fontSize: CGFloat = UserDefaults.standard.object(forKey: "fontSize") as? CGFloat ?? 14
    var wordWrap: Bool = UserDefaults.standard.object(forKey: "wordWrap") as? Bool ?? true
    var templatesFolderURL: URL?
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
