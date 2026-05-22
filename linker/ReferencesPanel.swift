import SwiftUI

struct ReferencesPanel: View {
    let filename: String
    let graph: VaultGraph
    var onOpenFile: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                referenceSection(
                    title: "Outgoing",
                    items: graph.outgoingReferences(for: filename).map { ref in
                        ReferenceItem(name: ref.filename, line: ref.line, column: ref.column, exists: graph.fileNameSet.contains(ref.filename))
                    }
                )

                referenceSection(
                    title: "Incoming",
                    items: graph.incomingReferences(for: filename).map { item in
                        ReferenceItem(name: item.source, line: item.reference.line, column: item.reference.column, exists: true)
                    }
                )

                Spacer()
            }
            .padding(12)
        }
    }

    private struct ReferenceItem {
        let name: String
        let line: Int
        let column: Int
        let exists: Bool
    }

    @ViewBuilder
    private func referenceSection(title: String, items: [ReferenceItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if items.isEmpty {
                Text("None")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Button {
                        onOpenFile(item.name)
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(item.name)
                                .font(.system(size: 12))
                                .foregroundStyle(item.exists ? .primary : .secondary)
                            Spacer()
                            Text("\(item.line):\(item.column)")
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
