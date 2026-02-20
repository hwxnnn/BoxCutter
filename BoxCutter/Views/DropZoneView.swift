import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {

    let onFileDrop: (URL) -> Void
    let onSelectFile: () -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "shippingbox")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("Drop a .pkg file here")
                .font(.title2)
                .foregroundStyle(.secondary)

            Button("Select File\u{2026}") {
                onSelectFile()
            }
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
        }
        .padding(20)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Drop Handling

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
            guard let data = data as? Data,
                  let urlString = String(data: data, encoding: .utf8),
                  let url = URL(string: urlString),
                  url.pathExtension.lowercased() == "pkg" else { return }

            DispatchQueue.main.async {
                onFileDrop(url)
            }
        }
        return true
    }
}

#Preview {
    DropZoneView(
        onFileDrop: { _ in },
        onSelectFile: {}
    )
    .frame(width: 520, height: 480)
}
