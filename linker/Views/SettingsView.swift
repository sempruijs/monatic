import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showVaultPicker = false

    var body: some View {
        @Bindable var appState = appState

        Form {
            Section("Vault") {
                HStack {
                    Text(appState.vaultURL?.path(percentEncoded: false) ?? "No vault selected")
                        .foregroundStyle(appState.vaultURL != nil ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if appState.vaultURL != nil {
                        Button("Clear") {
                            appState.clearVault()
                        }
                    }
                    Button("Change…") {
                        showVaultPicker = true
                    }
                }
            }

            Section("New Files") {
                Picker("Default folder", selection: $appState.newFileFolder) {
                    Text("/ (vault root)").tag("")
                    ForEach(appState.graph.subdirectories, id: \.self) { dir in
                        Text(dir).tag(dir)
                    }
                }
            }

            Section("Renaming") {
                Picker("Update references on rename", selection: $appState.renameReferenceBehavior) {
                    ForEach(RenameReferenceBehavior.allCases, id: \.self) { behavior in
                        Text(behavior.label).tag(behavior)
                    }
                }
            }

            Section("Editor") {
                HStack {
                    Text("Text Size")
                    Slider(value: $appState.fontSize, in: 8...48, step: 1) {
                        EmptyView()
                    }
                    Text("\(Int(appState.fontSize)) pt")
                        .monospacedDigit()
                        .frame(width: 45, alignment: .trailing)
                }
                Toggle("Word Wrap", isOn: $appState.wordWrap)
                Toggle("Auto Save", isOn: $appState.autoSave)
                Toggle("Dynamic Rendering", isOn: $appState.dynamicRendering)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fileImporter(isPresented: $showVaultPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                _ = url.startAccessingSecurityScopedResource()
                appState.setVault(url)
            }
        }
    }
}
