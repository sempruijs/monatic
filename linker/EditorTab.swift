import Observation
import Foundation

@Observable
class EditorTab: Identifiable {
    let id = UUID()
    var openFileURL: URL?
    var fileContent: String = ""
    var history = NavigationHistory()
    var cursorPositionToRestore: Int?
    var needsFocus: Bool = false
    var showReferences: Bool = false
    @ObservationIgnored var indexWorkItem: DispatchWorkItem?

    var title: String {
        openFileURL?.deletingPathExtension().lastPathComponent ?? "Empty"
    }

    func scheduleIndex(name: String, url: URL, graph: VaultGraph) {
        indexWorkItem?.cancel()
        let item = DispatchWorkItem { graph.indexFile(name: name, url: url) }
        indexWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }
}
