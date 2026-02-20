import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {

    let onFileDrop: (URL) -> Void
    let onSelectFile: () -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.system(size: 36))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)

            Text("Drop .pkg here")
                .font(.headline)
                .foregroundStyle(.secondary)

            Button("Select File\u{2026}") {
                onSelectFile()
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isTargeted ? Color.accentColor.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
            guard let data = data as? Data,
                  let urlString = String(data: data, encoding: .utf8),
                  let url = URL(string: urlString),
                  url.pathExtension.lowercased() == "pkg" else { return }
            DispatchQueue.main.async { onFileDrop(url) }
        }
        return true
    }
}

#Preview {
    DropZoneView(onFileDrop: { _ in }, onSelectFile: {})
        .frame(width: 320, height: 160)
}
