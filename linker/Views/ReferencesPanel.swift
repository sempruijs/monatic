import SwiftUI

struct ReferencesDragHandle: View {
    @Binding var width: CGFloat
    @State private var dragStartWidth: CGFloat?

    var body: some View {
        Color.clear
            .frame(width: 12)
            .overlay(Divider(), alignment: .center)
            .contentShape(Rectangle())
            .cursor(.resizeLeftRight)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = width
                        }
                        width = max(150, (dragStartWidth ?? width) - value.translation.width)
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
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
