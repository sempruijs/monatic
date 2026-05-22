import AppKit

class CompletionPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let panel: NSPanel
    private let tableView: NSTableView
    private(set) var items: [String] = []
    var onSelect: ((String) -> Void)?

    var isVisible: Bool { panel.isVisible }

    override init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.hasShadow = true
        panel.backgroundColor = .windowBackgroundColor
        panel.level = .popUpMenu

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false

        tableView = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.backgroundColor = .clear
        tableView.style = .plain

        scrollView.documentView = tableView

        super.init()

        panel.contentView = scrollView
        panel.setAccessibilityRole(.popover)
        panel.setAccessibilityLabel("Link completions")
        tableView.setAccessibilityRole(.list)
        tableView.setAccessibilityLabel("Suggestions")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(doubleClicked)
    }

    func show(at screenPoint: NSPoint, in parentWindow: NSWindow, items: [String]) {
        self.items = items
        tableView.reloadData()

        let height = min(CGFloat(items.count) * 22 + 4, 200)
        panel.setFrame(NSRect(x: screenPoint.x, y: screenPoint.y - height, width: 250, height: height), display: true)

        if !items.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }

        if panel.parent == nil {
            parentWindow.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        announceSelection()
    }

    func hide() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    func moveUp() {
        guard !items.isEmpty else { return }
        let row = max(tableView.selectedRow - 1, 0)
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        announceSelection()
    }

    func moveDown() {
        guard !items.isEmpty else { return }
        let row = min(tableView.selectedRow + 1, items.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        announceSelection()
    }

    private func announceSelection() {
        guard let item = selectedItem() else { return }
        let row = tableView.selectedRow
        let message = "\(item), \(row + 1) of \(items.count)"
        NSAccessibility.post(
            element: tableView,
            notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
    }

    func selectedItem() -> String? {
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return nil }
        return items[row]
    }

    @objc private func doubleClicked() {
        guard let item = selectedItem() else { return }
        onSelect?(item)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("CompletionCell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField ?? {
            let tf = NSTextField(labelWithString: "")
            tf.identifier = id
            tf.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            tf.lineBreakMode = .byTruncatingTail
            return tf
        }()
        cell.stringValue = items[row]
        return cell
    }
}
