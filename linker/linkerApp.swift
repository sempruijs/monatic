import SwiftUI

private struct QuickOpenKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

private struct SaveActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct NewFileActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct GoBackActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct GoForwardActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var showQuickOpen: Binding<Bool>? {
        get { self[QuickOpenKey.self] }
        set { self[QuickOpenKey.self] = newValue }
    }

    var saveAction: (() -> Void)? {
        get { self[SaveActionKey.self] }
        set { self[SaveActionKey.self] = newValue }
    }

    var newFileAction: (() -> Void)? {
        get { self[NewFileActionKey.self] }
        set { self[NewFileActionKey.self] = newValue }
    }

    var goBackAction: (() -> Void)? {
        get { self[GoBackActionKey.self] }
        set { self[GoBackActionKey.self] = newValue }
    }

    var goForwardAction: (() -> Void)? {
        get { self[GoForwardActionKey.self] }
        set { self[GoForwardActionKey.self] = newValue }
    }
}

@main
struct linkerApp: App {
    @State private var appState = AppState()
    @FocusedBinding(\.showQuickOpen) var showQuickOpen
    @FocusedValue(\.saveAction) var saveAction
    @FocusedValue(\.newFileAction) var newFileAction
    @FocusedValue(\.goBackAction) var goBackAction
    @FocusedValue(\.goForwardAction) var goForwardAction

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    newFileAction?()
                }
                .keyboardShortcut("n")
                .disabled(newFileAction == nil)

                Divider()

                Button("Quick Open") {
                    showQuickOpen = true
                }
                .keyboardShortcut("o")
                .disabled(showQuickOpen == nil)
            }
            CommandGroup(before: .toolbar) {
                Button("Back") {
                    goBackAction?()
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(goBackAction == nil)

                Button("Forward") {
                    goForwardAction?()
                }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(goForwardAction == nil)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    saveAction?()
                }
                .keyboardShortcut("s")
                .disabled(saveAction == nil)
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
