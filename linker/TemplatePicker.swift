import SwiftUI

struct TemplatePicker: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool
    var noteName: String
    var onInsert: (String) -> Void

    @State private var searchQuery = ""
    @State private var templates: [(name: String, url: URL)] = []
    @State private var selectedIndex: Int = 0
    @FocusState private var isSearchFocused: Bool

    private var filtered: [(name: String, url: URL)] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        if query.isEmpty { return templates }
        return templates.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                TextField("Search templates...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($isSearchFocused)
                    .onSubmit { submitSelection() }
                    .onKeyPress(.downArrow) {
                        if selectedIndex < filtered.count - 1 {
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

                if templates.isEmpty {
                    Text("No templates folder selected")
                        .foregroundStyle(.secondary)
                        .padding()
                } else if filtered.isEmpty {
                    Text("No matching templates")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(filtered.enumerated()), id: \.offset) { index, template in
                                    Text(template.name)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(index == selectedIndex ? Color.accentColor : Color.clear)
                                        .foregroundStyle(index == selectedIndex ? .white : .primary)
                                        .cornerRadius(4)
                                        .id(index)
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectTemplate(at: index) }
                                }
                            }
                        }
                        .frame(maxHeight: 300)
                        .onChange(of: selectedIndex) { _, newValue in
                            proxy.scrollTo(newValue)
                        }
                    }
                }
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
            templates = appState.templateFiles()
        }
        .onChange(of: searchQuery) { selectedIndex = 0 }
    }

    private func submitSelection() {
        guard !filtered.isEmpty, selectedIndex < filtered.count else { return }
        selectTemplate(at: selectedIndex)
    }

    private func selectTemplate(at index: Int) {
        let template = filtered[index]
        guard let content = try? String(contentsOf: template.url, encoding: .utf8) else { return }
        let processed = Self.processTemplate(content, title: noteName)
        onInsert(processed)
        close()
    }

    private func close() {
        isPresented = false
    }

    static func processTemplate(_ template: String, title: String) -> String {
        var result = template
        let now = Date()
        let formatter = DateFormatter()

        result = result.replacingOccurrences(of: "{{title}}", with: title)

        while let start = result.range(of: "{{date:") {
            guard let end = result[start.upperBound...].range(of: "}}") else { break }
            let format = String(result[start.upperBound..<end.lowerBound])
            formatter.dateFormat = convertMomentFormat(format)
            result.replaceSubrange(start.lowerBound..<end.upperBound, with: formatter.string(from: now))
        }

        formatter.dateFormat = "yyyy-MM-dd"
        result = result.replacingOccurrences(of: "{{date}}", with: formatter.string(from: now))

        while let start = result.range(of: "{{time:") {
            guard let end = result[start.upperBound...].range(of: "}}") else { break }
            let format = String(result[start.upperBound..<end.lowerBound])
            formatter.dateFormat = convertMomentFormat(format)
            result.replaceSubrange(start.lowerBound..<end.upperBound, with: formatter.string(from: now))
        }

        formatter.dateFormat = "HH:mm"
        result = result.replacingOccurrences(of: "{{time}}", with: formatter.string(from: now))

        return result
    }

    private static func convertMomentFormat(_ format: String) -> String {
        var result = format
        result = result.replacingOccurrences(of: "YYYY", with: "yyyy")
        result = result.replacingOccurrences(of: "YY", with: "yy")
        result = result.replacingOccurrences(of: "DD", with: "dd")
        return result
    }
}
