import SwiftUI

struct ImageViewer: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding()
                }
            } else {
                Text("Unable to load image")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadImage() }
        .onChange(of: url) { _, _ in loadImage() }
    }

    private func loadImage() {
        image = NSImage(contentsOf: url)
    }
}
