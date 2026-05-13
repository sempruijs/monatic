import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

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
                        appState.selectVault()
                    }
                }
            }

            Section("New Files") {
                HStack {
                    Text("Folder")
                    Spacer()
                    TextField("Vault root", text: $appState.newFileFolderRelativePath)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
                Text("Relative path from vault root. Leave empty for vault root.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            }

            Section("Templates") {
                HStack {
                    Text(appState.templatesFolderURL?.lastPathComponent ?? "No folder selected")
                        .foregroundStyle(appState.templatesFolderURL != nil ? .primary : .secondary)
                    Spacer()
                    Button("Select Folder") {
                        appState.selectTemplatesFolder()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .onChange(of: appState.fontSize) {
            UserDefaults.standard.set(appState.fontSize, forKey: "fontSize")
        }
        .onChange(of: appState.wordWrap) {
            UserDefaults.standard.set(appState.wordWrap, forKey: "wordWrap")
        }
        .onChange(of: appState.newFileFolderRelativePath) {
            UserDefaults.standard.set(appState.newFileFolderRelativePath, forKey: "newFileFolderRelativePath")
        }
    }
}
