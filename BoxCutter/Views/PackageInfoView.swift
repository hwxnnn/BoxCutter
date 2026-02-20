import SwiftUI

struct PackageInfoView: View {

    let info: PackageInfo
    let onCancel: () -> Void
    let onInstall: () -> Void
    @Binding var showDetails: Bool
    let detailsLoading: Bool

    private let settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            // Compact header
            HStack(spacing: 12) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 3) {
                    Text(info.packageName.isEmpty ? info.fileName : info.packageName)
                        .font(.headline)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(formattedSize(info.fileSize))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        signBadge
                    }
                }

                Spacer()
            }
            .padding(16)

            // Expanded details
            if showDetails && info.detailsLoaded {
                Divider()
                    .padding(.horizontal, 16)

                detailsContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()
                .padding(.horizontal, 16)
                .padding(.top, 4)

            // Bottom bar
            HStack(spacing: 10) {
                // Details toggle
                Button {
                    if info.detailsLoaded {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showDetails.toggle()
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if detailsLoading {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "chevron.right")
                                .rotationEffect(.degrees(showDetails ? 90 : 0))
                                .font(.caption2)
                        }
                        Text("Details")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(detailsLoading ? .tertiary : .secondary)
                .disabled(detailsLoading)

                Spacer()

                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)

                Button("Install") { onInstall() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Signing badge

    private var signBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: info.isSigned ? "checkmark.seal.fill" : "xmark.seal.fill")
                .font(.caption2)
            Text(info.isSigned ? "Signed" : "Unsigned")
                .font(.caption2)
        }
        .foregroundStyle(info.isSigned ? .green : .orange)
    }

    // MARK: - Expanded details

    private var detailsContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !info.packageIdentifier.isEmpty {
                    infoRow("Identifier", info.packageIdentifier)
                }
                if !info.version.isEmpty {
                    infoRow("Version", info.version)
                }
                infoRow("Location", info.installLocation)

                if !info.certificateChain.isEmpty {
                    infoRow("Certificate", info.certificateChain.joined(separator: " \u{2192} "))
                }

                // Script warnings
                if settings.showScriptWarnings && (info.hasPreinstallScript || info.hasPostinstallScript) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        VStack(alignment: .leading, spacing: 2) {
                            if info.hasPreinstallScript { Text("Pre-install script").font(.caption) }
                            if info.hasPostinstallScript { Text("Post-install script").font(.caption) }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.yellow.opacity(0.08))
                }

                // Payload files
                if settings.showPayloadFiles && !info.payloadFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Files (\(info.payloadFiles.count))")
                            .font(.caption.bold())
                            .padding(.horizontal, 16)
                            .padding(.top, 10)

                        ForEach(info.payloadFiles.prefix(50), id: \.self) { file in
                            Text(file)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 1)
                        }
                        if info.payloadFiles.count > 50 {
                            Text("\u{2026}and \(info.payloadFiles.count - 50) more")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 280)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

#Preview("Compact") {
    PackageInfoView(
        info: PackageInfo(
            fileURL: URL(fileURLWithPath: "/tmp/Example.pkg"),
            fileName: "Example.pkg", fileSize: 48_300_000,
            packageName: "Example Application", packageIdentifier: "com.example.app",
            version: "2.1.0", isSigned: true, signingStatus: "Signed"
        ),
        onCancel: {}, onInstall: {},
        showDetails: .constant(false), detailsLoading: false
    )
    .frame(width: 360)
}

#Preview("Loading") {
    PackageInfoView(
        info: PackageInfo(
            fileURL: URL(fileURLWithPath: "/tmp/Example.pkg"),
            fileName: "Example.pkg", fileSize: 48_300_000,
            packageName: "Example Application", packageIdentifier: "com.example.app",
            version: "2.1.0", isSigned: true, signingStatus: "Signed"
        ),
        onCancel: {}, onInstall: {},
        showDetails: .constant(false), detailsLoading: true
    )
    .frame(width: 360)
}
