import SwiftUI

struct CompletionView: View {

    let success: Bool
    let packageName: String
    let message: String
    let onDone: () -> Void
    var outputLines: [String] = []

    @State private var showLog = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(success ? .green : .red)

                VStack(alignment: .leading, spacing: 3) {
                    Text(success ? "Installation Complete" : "Installation Failed")
                        .font(.headline)

                    if success {
                        Text(packageName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }

                Spacer()
            }
            .padding(16)

            // Expandable install log
            if showLog && !outputLines.isEmpty {
                Divider()
                    .padding(.horizontal, 16)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(outputLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(8)
                }
                .background(.background.secondary)
                .frame(maxHeight: 200)
            }

            // Action bar
            Divider()
                .padding(.horizontal, 16)

            HStack(spacing: 8) {
                if !outputLines.isEmpty {
                    Button {
                        showLog.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.right")
                                .rotationEffect(.degrees(showLog ? 90 : 0))
                                .font(.caption2)
                            Text("Log").font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") { onDone() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

#Preview("Success with log") {
    CompletionView(
        success: true, packageName: "Example", message: "",
        onDone: {},
        outputLines: ["installer: Installing...", "installer:%percent:50.0", "installer: Done."]
    )
    .frame(width: 400)
}
