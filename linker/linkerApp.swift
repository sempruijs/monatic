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

private struct NewTabActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct CloseTabActionKey: FocusedValueKey {
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

    var newTabAction: (() -> Void)? {
        get { self[NewTabActionKey.self] }
        set { self[NewTabActionKey.self] = newValue }
    }

    var closeTabAction: (() -> Void)? {
        get { self[CloseTabActionKey.self] }
        set { self[CloseTabActionKey.self] = newValue }
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
    @FocusedValue(\.newTabAction) var newTabAction
    @FocusedValue(\.closeTabAction) var closeTabAction

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    newTabAction?()
                }
                .keyboardShortcut("t")
                .disabled(newTabAction == nil)

                Button("Close Tab") {
                    if let closeTabAction {
                        closeTabAction()
                    } else {
                        NSApp.keyWindow?.close()
                    }
                }
                .keyboardShortcut("w")

                Divider()

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
