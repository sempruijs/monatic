import Observation
import Foundation

@Observable
class NavigationHistory {
    struct Entry {
        let url: URL
        var cursorPosition: Int
    }

    private var stack: [Entry] = []
    private var currentIndex: Int = -1
    @ObservationIgnored var latestCursorPosition: Int = 0

    var canGoBack: Bool { currentIndex > 0 }
    var canGoForward: Bool { currentIndex < stack.count - 1 }

    func visit(_ url: URL) {
        if currentIndex >= 0, currentIndex < stack.count, stack[currentIndex].url == url { return }
        stack.removeSubrange((currentIndex + 1)...)
        stack.append(Entry(url: url, cursorPosition: 0))
        currentIndex = stack.count - 1
    }

    func saveCursorPosition(_ position: Int) {
        guard currentIndex >= 0, currentIndex < stack.count else { return }
        stack[currentIndex].cursorPosition = position
    }

    func goBack() -> Entry? {
        guard canGoBack else { return nil }
        currentIndex -= 1
        return stack[currentIndex]
    }

    func goForward() -> Entry? {
        guard canGoForward else { return nil }
        currentIndex += 1
        return stack[currentIndex]
    }
}
