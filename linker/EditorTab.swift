import Observation
import Foundation

@Observable
class EditorTab: Identifiable {
    let id = UUID()
    var openFileURL: URL?
    var fileContent: String = ""
    var history = NavigationHistory()
    var cursorPositionToRestore: Int?
    var showReferences: Bool = false

    var title: String {
        openFileURL?.deletingPathExtension().lastPathComponent ?? "Empty"
    }
}
