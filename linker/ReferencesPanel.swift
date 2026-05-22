import SwiftUI

struct ReferencesPanel: View {
    let outgoing: [ReferenceItem]
    let incoming: [ReferenceItem]
    var onOpenFile: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                referenceSection(title: "Outgoing", items: outgoing)
                referenceSection(title: "Incoming", items: incoming)
                Spacer()
            }
            .padding(12)
        }
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
                ForEach(items, id: \.name) { item in
                    Text(item.name)
                        .font(.system(size: 12))
                        .foregroundStyle(item.exists ? .primary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .contentShape(Rectangle())
                        .onTapGesture { onOpenFile(item.name) }
                }
            }
        }
    }
}

struct ReferenceItem: Equatable {
    let name: String
    let line: Int
    let column: Int
    let exists: Bool
}
