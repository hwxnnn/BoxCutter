import SwiftUI
import UniformTypeIdentifiers

struct PackageInfoView: View {

    let info: PackageInfo
    let onCancel: () -> Void
    let onInstall: () -> Void
    @Binding var showDetails: Bool
    let detailsLoading: Bool

    private let settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            // PINNED: Header — never moves
            header
                .padding(16)

            // EXPANDABLE: Details section — grows/shrinks here
            if showDetails && info.detailsLoaded {
                Divider()
                    .padding(.horizontal, 16)

                detailsContent
            }

            // PINNED: Divider + action bar — never moves relative to header when collapsed
            Divider()
                .padding(.horizontal, 16)

            actionBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .clipped()
    }

    // MARK: - Header

    private var pkgIcon: NSImage {
        NSWorkspace.shared.icon(for: UTType(filenameExtension: "pkg") ?? .package)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: pkgIcon)
                .resizable()
                .frame(width: 32, height: 32)

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
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                if info.detailsLoaded {
                    showDetails.toggle()
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
            VStack(alignment: .leading, spacing: 8) {
                // Info rows
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
                }

                // Script warnings as pills
                if settings.showScriptWarnings && (info.hasPreinstallScript || info.hasPostinstallScript) {
                    HStack(spacing: 6) {
                        if info.hasPreinstallScript {
                            warningPill("Pre-install script")
                        }
                        if info.hasPostinstallScript {
                            warningPill("Post-install script")
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Payload files
                if settings.showPayloadFiles && !info.payloadFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Payload (\(info.payloadFiles.count) files)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)

                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(info.payloadFiles, id: \.self) { file in
                                Text(file)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 280)
    }

    // MARK: - Helpers

    private func warningPill(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
            Text(text)
                .font(.caption2)
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.orange.opacity(0.1), in: Capsule())
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
    .frame(width: 400)
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
    .frame(width: 400)
}
