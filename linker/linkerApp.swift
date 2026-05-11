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

private struct NewTabActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct GoBackActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct GoForwardActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct IncreaseFontActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct DecreaseFontActionKey: FocusedValueKey {
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

    var newTabAction: (() -> Void)? {
        get { self[NewTabActionKey.self] }
        set { self[NewTabActionKey.self] = newValue }
    }

    var goBackAction: (() -> Void)? {
        get { self[GoBackActionKey.self] }
        set { self[GoBackActionKey.self] = newValue }
    }

    var goForwardAction: (() -> Void)? {
        get { self[GoForwardActionKey.self] }
        set { self[GoForwardActionKey.self] = newValue }
    }

    var increaseFontAction: (() -> Void)? {
        get { self[IncreaseFontActionKey.self] }
        set { self[IncreaseFontActionKey.self] = newValue }
    }

    var decreaseFontAction: (() -> Void)? {
        get { self[DecreaseFontActionKey.self] }
        set { self[DecreaseFontActionKey.self] = newValue }
    }
}

@main
struct linkerApp: App {
    @State private var appState = AppState()
    @FocusedBinding(\.showQuickOpen) var showQuickOpen
    @FocusedValue(\.saveAction) var saveAction
    @FocusedValue(\.newFileAction) var newFileAction
    @FocusedValue(\.newTabAction) var newTabAction
    @FocusedValue(\.goBackAction) var goBackAction
    @FocusedValue(\.goForwardAction) var goForwardAction
    @FocusedValue(\.increaseFontAction) var increaseFontAction
    @FocusedValue(\.decreaseFontAction) var decreaseFontAction

    var body: some Scene {
        WindowGroup(id: "editor") {
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

                Button("New Tab") {
                    newTabAction?()
                }
                .keyboardShortcut("t")
                .disabled(newTabAction == nil)

                Divider()

                Button("Quick Open") {
                    showQuickOpen = true
                }
                .keyboardShortcut("o")
                .disabled(showQuickOpen == nil)
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Close Tab") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w")
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
            CommandGroup(after: .toolbar) {
                Button("Increase Size") {
                    increaseFontAction?()
                }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(increaseFontAction == nil)

                Button("Decrease Size") {
                    decreaseFontAction?()
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(decreaseFontAction == nil)
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
