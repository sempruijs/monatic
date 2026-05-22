import SwiftUI

struct QuickOpenPanel: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool
    var onOpenFile: (URL) -> Void

    @State private var searchQuery = ""
    @State private var searchResults: [VaultGraph.FileEntry] = []
    @State private var selectedIndex: Int = 0
    @State private var showingRecents = true
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                TextField("Search files...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($isSearchFocused)
                    .onSubmit(openSelected)
                    .onKeyPress(.downArrow) {
                        if selectedIndex < searchResults.count - 1 {
                            selectedIndex += 1
                        }
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        if selectedIndex > 0 {
                            selectedIndex -= 1
                        }
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        close()
                        return .handled
                    }
                    .padding(12)

                Divider()

                if showingRecents && !searchResults.isEmpty {
                    HStack {
                        Text("Recent")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(searchResults.enumerated()), id: \.element.name) { index, result in
                                resultRow(result: result, index: index)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .onChange(of: selectedIndex) { _, newValue in
                        proxy.scrollTo(searchResults[safe: newValue]?.name, anchor: .center)
                    }
                }
                .frame(maxHeight: 300)
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 20)
            .frame(width: 500)
            .padding(.top, 50)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.3))
        .onTapGesture { close() }
        .onExitCommand { close() }
        .onAppear {
            updateResults()
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
        .onChange(of: searchQuery) {
            updateResults()
        }
    }

    private func resultRow(result: VaultGraph.FileEntry, index: Int) -> some View {
        let isSelected = index == selectedIndex
        return Text(result.name)
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor : Color.clear)
            .foregroundStyle(isSelected ? .white : .primary)
            .cornerRadius(4)
            .contentShape(Rectangle())
            .id(result.name)
            .onTapGesture {
                select(result.url)
            }
    }

    private func updateResults() {
        searchResults = appState.graph.search(searchQuery)
        showingRecents = searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
        selectedIndex = 0
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
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
