import SwiftUI

/// Shown when a mounted disk image contains no .app bundles. The volume has been
/// re-attached browsable by this point, so it behaves like a normal double-click mount.
struct DMGNoAppsView: View {

    let info: DMGVolumeInfo
    let onClose: () -> Void
    let onUnmount: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 3) {
                    Text("No Apps Detected")
                        .font(.headline)
                    Text(info.dmgFileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 16)

            HStack(spacing: 8) {
                Button("Close") { onClose() }

                Spacer()

                Button("Unmount") { onUnmount() }

                Button("Open in Finder") { onOpen() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

#Preview {
    DMGNoAppsView(
        info: DMGVolumeInfo(
            dmgURL: URL(fileURLWithPath: "/Users/example/Downloads/Fonts.dmg"),
            dmgFileName: "Fonts.dmg",
            mountPoint: URL(fileURLWithPath: "/Volumes/Fonts")
        ),
        onClose: {},
        onUnmount: {},
        onOpen: {}
    )
    .frame(width: 400)
}
