import SwiftUI

struct QuickOpenPanel: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool
    var onOpenFile: (URL) -> Void

    @State private var searchQuery = ""
    @State private var searchResults: [VaultGraph.FileEntry] = []
    @State private var selectedIndex: Int = 0
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                TextField("Search files...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($isSearchFocused)
                    .onSubmit {
                        if !searchResults.isEmpty {
                            select(searchResults[selectedIndex].url)
                        }
                    }
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
                    .padding(12)

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(searchResults.enumerated()), id: \.offset) { index, result in
                                Button {
                                    select(result.url)
                                } label: {
                                    Text(result.name)
                                        .font(.system(size: 13))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(index == selectedIndex ? Color.accentColor : Color.clear)
                                        .foregroundStyle(index == selectedIndex ? .white : .primary)
                                        .cornerRadius(4)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(index)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .onChange(of: selectedIndex) { _, newValue in
                        proxy.scrollTo(newValue, anchor: .center)
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
            isSearchFocused = true
            searchResults = appState.graph.search("")
        }
        .onChange(of: searchQuery) {
            searchResults = appState.graph.search(searchQuery)
            selectedIndex = 0
        }
    }

    private func select(_ url: URL) {
        onOpenFile(url)
        close()
    }

    private func close() {
        isPresented = false
    }
}
