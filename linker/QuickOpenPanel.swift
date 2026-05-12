import AppKit
import SwiftUI

private struct AutoFocusTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var onArrowDown: (() -> Void)?
    var onArrowUp: (() -> Void)?

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
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onArrowDown?()
                return true
            }
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onArrowUp?()
                return true
            }
            return false
        }
    }
}

private struct ResultsTableView: NSViewRepresentable {
    var results: [SearchIndex.Result]
    var selectedIndex: Int
    var onSelect: (URL) -> Void
    var onSelectionChanged: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let tableView = NSTableView()
        let column = NSTableColumn(identifier: .init("name"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 28
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = false
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.action = #selector(Coordinator.rowClicked(_:))
        tableView.target = context.coordinator
        tableView.refusesFirstResponder = true

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = context.coordinator.tableView else { return }
        context.coordinator.parent = self

        let oldNames = context.coordinator.cachedNames
        let newNames = results.map(\.name)
        if oldNames != newNames {
            context.coordinator.cachedNames = newNames
            context.coordinator.cachedAttr = results.map { Self.highlightedString(for: $0) }
            tableView.reloadData()
        }

        if !results.isEmpty && selectedIndex >= 0 && selectedIndex < results.count
            && tableView.selectedRow != selectedIndex
        {
            tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
            tableView.scrollRowToVisible(selectedIndex)
        }
    }

    static func highlightedString(for result: SearchIndex.Result) -> NSAttributedString {
        let name = result.name
        let str = NSMutableAttributedString(string: name, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
        ])
        for range in result.highlights {
            let nsRange = NSRange(range, in: name)
            str.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 13), range: nsRange)
        }
        return str
    }

    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: ResultsTableView
        weak var tableView: NSTableView?
        var cachedNames: [String] = []
        var cachedAttr: [NSAttributedString] = []

        init(_ parent: ResultsTableView) { self.parent = parent }

        func numberOfRows(in tableView: NSTableView) -> Int {
            cachedAttr.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < cachedAttr.count else { return nil }
            let cellID = NSUserInterfaceItemIdentifier("ResultCell")
            let cell: NSTextField
            if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTextField {
                cell = existing
            } else {
                cell = NSTextField(labelWithString: "")
                cell.identifier = cellID
                cell.lineBreakMode = .byTruncatingTail
                cell.drawsBackground = false
                cell.isBordered = false
            }
            cell.attributedStringValue = cachedAttr[row]
            return cell
        }

        @objc func rowClicked(_ sender: Any?) {
            guard let tableView = tableView else { return }
            let row = tableView.clickedRow
            if row >= 0 && row < parent.results.count {
                parent.onSelect(parent.results[row].url)
            }
        }
    }
}

struct QuickOpenPanel: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool
    var onOpenFile: (URL) -> Void

    @State private var searchQuery = ""
    @State private var searchResults: [SearchIndex.Result] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedIndex: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                AutoFocusTextField(
                    text: $searchQuery,
                    placeholder: "Search files...",
                    onSubmit: {
                        if !searchResults.isEmpty {
                            select(searchResults[selectedIndex].url)
                        }
                    },
                    onArrowDown: {
                        if selectedIndex < searchResults.count - 1 {
                            selectedIndex += 1
                        }
                    },
                    onArrowUp: {
                        if selectedIndex > 0 {
                            selectedIndex -= 1
                        }
                    }
                )
                .padding(12)

                Divider()

                ResultsTableView(
                    results: searchResults,
                    selectedIndex: selectedIndex,
                    onSelect: { select($0) },
                    onSelectionChanged: { selectedIndex = $0 }
                )
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
            searchResults = appState.graph.searchIndex.search("")
        }
        .onChange(of: searchQuery) {
            searchTask?.cancel()
            let query = searchQuery
            let index = appState.graph.searchIndex
            searchTask = Task.detached(priority: .userInitiated) {
                try? await Task.sleep(for: .milliseconds(30))
                guard !Task.isCancelled else { return }
                let results = index.search(query, cancelled: { Task.isCancelled })
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.searchResults = results
                    self.selectedIndex = 0
                }
            }
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
