import SwiftUI
import AppKit

struct DMGThinningChoiceView: View {
    let info: DMGInfo
    let onCancel: () -> Void
    let onNo: () -> Void
    let onYes: () -> Void

    var body: some View {
        if let app = info.appsAwaitingThinningDecision.first {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.appURL.path))
                        .resizable()
                        .frame(width: 44, height: 44)
                        .accessibilityLabel(app.appName)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Thin this app?")
                            .font(.headline)
                        if info.selectedUniversalApps.count > 1 {
                            Text(app.appName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(savingsMessage(for: app))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Label(app.isCodeSigned ? "Signed" : "Unsigned",
                          systemImage: app.isCodeSigned ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .font(.caption2)
                        .foregroundStyle(app.isCodeSigned ? .green : .orange)
                }
                .padding(16)

                Divider()
                    .padding(.horizontal, 16)

                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Button("No", action: onNo)
                    Button("Yes", action: onYes)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
    }

    private func savingsMessage(for app: DMGAppEntry) -> String {
        guard app.estimatedBytesSaved > 0 else { return "Remove code this Mac doesn’t need." }
        let size = ByteCountFormatter.string(fromByteCount: app.estimatedBytesSaved, countStyle: .file)
        return "You’ll save \(size)."
    }
}
