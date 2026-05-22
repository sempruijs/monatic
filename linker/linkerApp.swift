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

private struct DeleteFileActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct DailyNoteActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ToggleReferencesActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ShowTemplatePickerKey: FocusedValueKey {
    typealias Value = Binding<Bool>
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

    var deleteFileAction: (() -> Void)? {
        get { self[DeleteFileActionKey.self] }
        set { self[DeleteFileActionKey.self] = newValue }
    }

    var dailyNoteAction: (() -> Void)? {
        get { self[DailyNoteActionKey.self] }
        set { self[DailyNoteActionKey.self] = newValue }
    }

    var toggleReferencesAction: (() -> Void)? {
        get { self[ToggleReferencesActionKey.self] }
        set { self[ToggleReferencesActionKey.self] = newValue }
    }

    var showTemplatePicker: Binding<Bool>? {
        get { self[ShowTemplatePickerKey.self] }
        set { self[ShowTemplatePickerKey.self] = newValue }
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
    @FocusedValue(\.deleteFileAction) var deleteFileAction
    @FocusedValue(\.dailyNoteAction) var dailyNoteAction
    @FocusedValue(\.toggleReferencesAction) var toggleReferencesAction
    @FocusedBinding(\.showTemplatePicker) var showTemplatePicker

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

                Button("Daily Note") {
                    dailyNoteAction?()
                }
                .keyboardShortcut("d")
                .disabled(dailyNoteAction == nil)

                Button("Insert Template") {
                    showTemplatePicker = true
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(showTemplatePicker == nil)

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

                Divider()

                Button("Toggle References") {
                    toggleReferencesAction?()
                }
                .keyboardShortcut("l")
                .disabled(toggleReferencesAction == nil)
            }
            CommandGroup(after: .toolbar) {
                Button("Increase Text Size") {
                    appState.fontSize = min(appState.fontSize + 1, 48)
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Decrease Text Size") {
                    appState.fontSize = max(appState.fontSize - 1, 8)
                }
                .keyboardShortcut("-", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    saveAction?()
                }
                .keyboardShortcut("s")
                .disabled(saveAction == nil)

                Divider()

                Button("Delete File…") {
                    deleteFileAction?()
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(deleteFileAction == nil)
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
