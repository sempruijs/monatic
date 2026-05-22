import SwiftUI

struct ReferencesPanel: View {
    let outgoing: [ReferenceItem]
    let incoming: [ReferenceItem]
    var fontSize: CGFloat
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
                .font(.system(size: fontSize * 0.8))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if items.isEmpty {
                Text("None")
                    .font(.system(size: fontSize))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(items, id: \.name) { item in
                    Text(item.name)
                        .font(.system(size: fontSize))
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

struct ReferencesDragHandle: View {
    @Binding var width: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .overlay(Divider(), alignment: .leading)
            .contentShape(Rectangle())
            .cursor(.resizeLeftRight)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        width = max(150, width - value.translation.width)
                    }
            )
    }
}

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}

struct ReferenceItem: Equatable {
    let name: String
    let line: Int
    let column: Int
    let exists: Bool
}
