import AppKit
import SwiftUI

private struct AutoFocusTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: NSFont.systemFontSize(for: .large))
        field.focusRingType = .none
        field.delegate = context.coordinator
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AutoFocusTextField
        init(_ parent: AutoFocusTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

struct QuickOpenPanel: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool
    var onOpenFile: (URL) -> Void

    @State private var searchQuery = ""

    private var searchResults: [VaultGraph.SearchResult] {
        appState.graph.fuzzySearch(searchQuery)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                AutoFocusTextField(
                    text: $searchQuery,
                    placeholder: "Search files...",
                    onSubmit: {
                        if let first = searchResults.first {
                            select(first.url)
                        }
                    }
                )
                .padding(12)

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(searchResults, id: \.name) { result in
                            Button {
                                select(result.url)
                            } label: {
                                highlightedText(
                                    name: result.name,
                                    highlights: result.highlights
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
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
    }

    private func highlightedText(name: String, highlights: [Range<String.Index>]) -> Text {
        guard !highlights.isEmpty else {
            return Text(name)
        }

        var attributed = AttributedString()
        var current = name.startIndex

        for range in highlights {
            if current < range.lowerBound {
                attributed.append(AttributedString(String(name[current..<range.lowerBound])))
            }
            var bold = AttributedString(String(name[range]))
            bold.inlinePresentationIntent = .stronglyEmphasized
            attributed.append(bold)
            current = range.upperBound
        }

        if current < name.endIndex {
            attributed.append(AttributedString(String(name[current..<name.endIndex])))
        }

        return Text(attributed)
    }

    private func select(_ url: URL) {
        onOpenFile(url)
        close()
    }

    private func close() {
        isPresented = false
    }
}
