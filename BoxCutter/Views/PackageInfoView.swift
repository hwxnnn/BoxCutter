import SwiftUI

struct PackageInfoView: View {

    let info: PackageInfo
    let onCancel: () -> Void
    let onInstall: () -> Void
    @Binding var showDetails: Bool
    let onLoadDetails: () -> Void

    private let settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            // Compact header — always visible
            HStack(spacing: 10) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Details section
            if showDetails {
                Divider()
                detailsContent
            }

            Divider()

            // Action bar
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDetails.toggle()
                    }
                    if showDetails && !info.detailsLoaded {
                        onLoadDetails()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(showDetails ? 90 : 0))
                        .font(.caption)
                    Text("Details")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)

                Button("Install") { onInstall() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Compact signing badge

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
                if settings.showScriptWarnings && info.detailsLoaded && (info.hasPreinstallScript || info.hasPostinstallScript) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        VStack(alignment: .leading, spacing: 1) {
                            if info.hasPreinstallScript { Text("Pre-install script").font(.caption) }
                            if info.hasPostinstallScript { Text("Post-install script").font(.caption) }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(.yellow.opacity(0.08))
                }

                // Loading indicator for details
                if !info.detailsLoaded {
                    HStack {
                        ProgressView().controlSize(.mini)
                        Text("Loading details\u{2026}").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(8)
                }

                // Payload files
                if settings.showPayloadFiles && !info.payloadFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Files (\(info.payloadFiles.count))")
                            .font(.caption.bold())
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

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
                }
            }
            .padding(.vertical, 4)
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
        .padding(.vertical, 2)
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
        showDetails: .constant(false), onLoadDetails: {}
    )
    .frame(width: 360)
}
