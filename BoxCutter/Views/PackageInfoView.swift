import SwiftUI

struct PackageInfoView: View {

    let info: PackageInfo
    let onCancel: () -> Void
    let onInstall: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading) {
                    Text(info.fileName)
                        .font(.title3.bold())
                    Text(info.packageName.isEmpty ? info.packageIdentifier : info.packageName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()

            Divider()

            // Info grid
            ScrollView {
                VStack(spacing: 0) {
                    infoRow("Identifier", info.packageIdentifier.isEmpty ? "N/A" : info.packageIdentifier)
                    infoRow("Version", info.version.isEmpty ? "N/A" : info.version)
                    infoRow("Size", formattedSize(info.fileSize))
                    infoRow("Install Location", info.installLocation)
                    infoRow("Signing", info.signingStatus)

                    if !info.certificateChain.isEmpty {
                        infoRow("Certificate", info.certificateChain.joined(separator: " → "))
                    }

                    // Script warnings
                    if info.hasPreinstallScript || info.hasPostinstallScript {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            VStack(alignment: .leading) {
                                if info.hasPreinstallScript {
                                    Text("Contains pre-install script")
                                }
                                if info.hasPostinstallScript {
                                    Text("Contains post-install script")
                                }
                            }
                            .font(.callout)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.yellow.opacity(0.1))
                    }

                    // Payload files
                    if !info.payloadFiles.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Files (\(info.payloadFiles.count))")
                                .font(.headline)
                                .padding(.horizontal)
                                .padding(.top, 12)

                            List(info.payloadFiles, id: \.self) { file in
                                Text(file)
                                    .font(.system(.caption, design: .monospaced))
                            }
                            .frame(height: 160)
                            .scrollContentBackground(.hidden)
                        }
                    }
                }
            }

            Divider()

            // Action bar
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Install") {
                    onInstall()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
            .padding()
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)

            Text(value)
                .font(.callout)
                .textSelection(.enabled)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
