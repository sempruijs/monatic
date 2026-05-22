import Observation
import Foundation

enum TabContentType {
    case markdown
    case pdf
    case unsupported

    static func from(url: URL) -> TabContentType {
        switch url.pathExtension.lowercased() {
        case "md", "markdown", "txt": return .markdown
        case "pdf": return .pdf
        default: return .unsupported
        }
    }

    static let supportedExtensions: Set<String> = ["md", "markdown", "txt", "pdf"]
}

@Observable
class EditorTab: Identifiable {
    let id = UUID()
    var openFileURL: URL?
    var fileContent: String = ""
    var history = NavigationHistory()
    var cursorPositionToRestore: Int?
    var needsFocus: Bool = false
    var needsNameFieldFocus: Bool = false
    var showReferences: Bool = false
    @ObservationIgnored var indexWorkItem: DispatchWorkItem?

    var contentType: TabContentType {
        guard let url = openFileURL else { return .markdown }
        return TabContentType.from(url: url)
    }

    var title: String {
        guard let url = openFileURL else { return "Empty" }
        return contentType == .markdown
            ? url.deletingPathExtension().lastPathComponent
            : url.lastPathComponent
    }

    func scheduleIndex(name: String, url: URL, graph: VaultGraph) {
        indexWorkItem?.cancel()
        let item = DispatchWorkItem { graph.indexFile(name: name, url: url) }
        indexWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }
}
