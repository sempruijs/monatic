import SwiftUI

struct TemplatePicker: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool
    var currentTitle: String
    var onInsert: (String) -> Void

    @State private var searchQuery = ""
    @State private var templates: [TemplateEntry] = []
    @State private var filtered: [TemplateEntry] = []
    @State private var selectedIndex: Int = 0
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            panel
                .padding(.top, 50)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
        .onTapGesture { close() }
        .onExitCommand { close() }
        .onAppear {
            loadTemplates()
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
        .onChange(of: searchQuery) {
            filterTemplates()
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            TextField("Search templates...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isSearchFocused)
                .accessibilityLabel("Search templates")
                .onSubmit(insertSelected)
                .onKeyPress(.downArrow) {
                    if selectedIndex < filtered.count - 1 { selectedIndex += 1 }
                    announceSelection()
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    if selectedIndex > 0 { selectedIndex -= 1 }
                    announceSelection()
                    return .handled
                }
                .onKeyPress(.escape) {
                    close()
                    return .handled
                }
                .padding(12)

            Divider()

            if filtered.isEmpty {
                Text(templates.isEmpty ? "No template folder configured" : "No matching templates")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                resultsList
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .frame(width: 500)
    }

    private var resultsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, entry in
                    resultRow(entry, isSelected: index == selectedIndex)
                        .onTapGesture { insert(entry) }
                }
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Templates, \(filtered.count) items")
        }
        .frame(maxHeight: 300)
    }

    private func resultRow(_ entry: TemplateEntry, isSelected: Bool) -> some View {
        Text(entry.name)
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor : Color.clear)
            .foregroundStyle(isSelected ? .white : .primary)
            .cornerRadius(4)
            .contentShape(Rectangle())
            .accessibilityLabel(entry.name)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityRemoveTraits(isSelected ? [] : [.isSelected])
    }

    private func loadTemplates() {
        guard let folderURL = appState.templateFolderURL else {
            templates = []
            filtered = []
            return
        }
        templates = TemplateEngine.loadTemplates(from: folderURL)
        filtered = templates
    }

    private func filterTemplates() {
        let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty {
            filtered = templates
        } else {
            filtered = templates.filter { $0.name.lowercased().contains(query) }
        }
        selectedIndex = 0
    }

    private func insertSelected() {
        guard selectedIndex < filtered.count else { return }
        insert(filtered[selectedIndex])
    }

    private func insert(_ entry: TemplateEntry) {
        guard let content = try? String(contentsOf: entry.url, encoding: .utf8) else { return }
        let processed = TemplateEngine.process(content, title: currentTitle)
        onInsert(processed)
        close()
    }

    private func close() {
        isPresented = false
    }

    private func announceSelection() {
        guard selectedIndex < filtered.count else { return }
        let entry = filtered[selectedIndex]
        let message = "\(entry.name), \(selectedIndex + 1) of \(filtered.count)"
        NSAccessibility.post(
            element: NSApp.mainWindow as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
    }
}
