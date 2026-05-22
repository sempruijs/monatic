import SwiftUI

struct QuickOpenPanel: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool
    var onOpenFile: (URL) -> Void

    @State private var searchQuery = ""
    @State private var searchResults: [VaultGraph.SearchResult] = []
    @State private var selectedIndex: Int = 0
    @State private var showingRecents = true
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
            searchResults = appState.graph.search("")
            showingRecents = true
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
        .onChange(of: searchQuery) {
            searchResults = appState.graph.search(searchQuery)
            showingRecents = searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
            selectedIndex = 0
            DispatchQueue.main.async { announceSelection() }
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            TextField("Search files...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isSearchFocused)
                .accessibilityLabel("Search files")
                .onSubmit(openSelected)
                .onKeyPress(.downArrow) {
                    if selectedIndex < searchResults.count - 1 { selectedIndex += 1 }
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

            if showingRecents && !searchResults.isEmpty {
                Text("RECENT")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
            }

            resultsList
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
                ForEach(searchResults) { result in
                    resultRow(result)
                }
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Search results, \(searchResults.count) items")
        }
        .frame(maxHeight: 300)
    }

    private func resultRow(_ result: VaultGraph.SearchResult) -> some View {
        let isSelected = result.id == searchResults[safe: selectedIndex]?.id
        return Text(result.name)
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor : Color.clear)
            .foregroundStyle(isSelected ? .white : .primary)
            .cornerRadius(4)
            .contentShape(Rectangle())
            .onTapGesture { select(result.url) }
            .accessibilityLabel(result.name)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityRemoveTraits(isSelected ? [] : [.isSelected])
    }

    private func openSelected() {
        guard let result = searchResults[safe: selectedIndex] else { return }
        select(result.url)
    }

    private func select(_ url: URL) {
        onOpenFile(url)
        close()
    }

    private func close() {
        isPresented = false
    }

    private func announceSelection() {
        guard let result = searchResults[safe: selectedIndex] else { return }
        let message = "\(result.name), \(selectedIndex + 1) of \(searchResults.count)"
        NSAccessibility.post(
            element: NSApp.mainWindow as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
