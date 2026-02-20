import SwiftUI
import UniformTypeIdentifiers

struct PackageInfoView: View {

    let info: PackageInfo
    let onCancel: () -> Void
    let onInstall: () -> Void
    @Binding var showDetails: Bool
    let detailsLoading: Bool
    @Binding var installTarget: String
    @Binding var showLicense: Bool

    private let settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            // PINNED: Header
            header
                .padding(16)

            // EXPANDABLE: Details
            if showDetails && info.detailsLoaded {
                Divider()
                    .padding(.horizontal, 16)

                detailsContent
            }

            // PINNED: Action bar
            Divider()
                .padding(.horizontal, 16)

            actionBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
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
        HStack(spacing: 8) {
            // Details toggle
            Button {
                if info.detailsLoaded { showDetails.toggle() }
            } label: {
                HStack(spacing: 4) {
                    if detailsLoading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(showDetails ? 90 : 0))
                            .font(.caption2)
                    }
                    Text("Details").font(.caption)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(detailsLoading ? .tertiary : .secondary)
            .disabled(detailsLoading)

            // License button (only if license exists)
            if !info.licenseText.isEmpty {
                Button {
                    showLicense.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.text").font(.caption2)
                        Text("License").font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .popover(isPresented: $showLicense, arrowEdge: .top) {
                    ScrollView {
                        Text(info.licenseText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(12)
                    }
                    .frame(width: 380, height: 300)
                }
            }

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

    private var filteredPayloadFiles: [String] {
        info.payloadFiles.filter { file in
            let trimmed = file.trimmingCharacters(in: CharacterSet(charactersIn: "./"))
            return !trimmed.isEmpty && !file.hasSuffix("/")
        }
    }

    private var detailsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // — Metadata section
                if !info.packageIdentifier.isEmpty || !info.version.isEmpty {
                    VStack(spacing: 0) {
                        if !info.packageIdentifier.isEmpty {
                            infoRow("Identifier", info.packageIdentifier)
                        }
                        if !info.version.isEmpty {
                            infoRow("Version", info.version)
                        }
                    }
                }

                // — Location section
                VStack(alignment: .leading, spacing: 6) {
                    Text("Location")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)

                    Picker("", selection: $installTarget) {
                        Text("/ (All Users)").tag("/")
                        ForEach(mountedVolumes, id: \.self) { vol in
                            Text(vol).tag(vol)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .padding(.horizontal, 16)
                }

                // — Security section
                if !info.certificateChain.isEmpty || (settings.showScriptWarnings && (info.hasPreinstallScript || info.hasPostinstallScript)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Security")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)

                        if !info.certificateChain.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(info.certificateChain.enumerated()), id: \.offset) { index, cert in
                                    HStack(spacing: 4) {
                                        if index == 0 {
                                            Image(systemName: "checkmark.seal.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.green)
                                        } else {
                                            Text(String(repeating: " ", count: 2))
                                                .font(.caption2)
                                            Image(systemName: "arrow.turn.down.right")
                                                .font(.system(size: 8))
                                                .foregroundStyle(.tertiary)
                                        }
                                        Text(cert)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                        }

                        if settings.showScriptWarnings && (info.hasPreinstallScript || info.hasPostinstallScript) {
                            HStack(spacing: 6) {
                                if info.hasPreinstallScript { warningPill("Pre-install script") }
                                if info.hasPostinstallScript { warningPill("Post-install script") }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }

                // — Payload files section
                if settings.showPayloadFiles && !filteredPayloadFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Payload (\(filteredPayloadFiles.count) files)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 1) {
                                ForEach(filteredPayloadFiles, id: \.self) { file in
                                    Text(file)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 120)
                        .background(.background.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 360)
    }

    // MARK: - Helpers

    private var mountedVolumes: [String] {
        FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        )?
        .compactMap { url in
            let path = url.path
            return path == "/" ? nil : path
        } ?? []
    }

    private func warningPill(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
            Text(text).font(.caption2)
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
        showDetails: .constant(false), detailsLoading: false,
        installTarget: .constant("/"), showLicense: .constant(false)
    )
    .frame(width: 400)
}
