import AppKit
import Foundation

@Observable
class AppState {
    var graph = VaultGraph()
    var vaultURL: URL?
    var fontSize: CGFloat = UserDefaults.standard.object(forKey: "fontSize") as? CGFloat ?? 14
    var wordWrap: Bool = UserDefaults.standard.object(forKey: "wordWrap") as? Bool ?? true
    private var hasRestored = false

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
}
