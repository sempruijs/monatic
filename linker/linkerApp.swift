import SwiftUI

private struct QuickOpenKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var showQuickOpen: Binding<Bool>? {
        get { self[QuickOpenKey.self] }
        set { self[QuickOpenKey.self] = newValue }
    }
}

@main
struct linkerApp: App {
    @FocusedBinding(\.showQuickOpen) var showQuickOpen

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Quick Open") {
                    showQuickOpen = true
                }
                .keyboardShortcut("o")
                .disabled(showQuickOpen == nil)
            }
        }
    }
}
