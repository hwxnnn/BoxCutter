import SwiftUI

struct InstallingView: View {

    let packageName: String
    let outputLines: [String]
    let progress: Double
    private let settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Installing \(packageName)\u{2026}")
                    .font(.title3.bold())
                Spacer()
            }
            .padding()

            Divider()

            if settings.showVerboseOutput {
                // Verbose log
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(outputLines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                    .id(index)
                            }
                        }
                        .padding(8)
                    }
                    .background(.background.secondary)
                    .onChange(of: outputLines.count) { _, _ in
                        if let last = outputLines.indices.last {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }

                Divider()
            } else {
                Spacer()
            }

            if settings.showProgressBar {
                VStack(spacing: 4) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)

                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding()
            }
        }
    }
}

#Preview {
    InstallingView(
        packageName: "Example Application",
        outputLines: [
            "installer: Package name is Example Application",
            "installer: Installing at base path /",
            "installer: Preparing for installation...",
            "installer:PHASE:Preparing for installation...",
            "installer:%percent:0.5",
            "installer:%percent:12.0",
            "installer:%percent:35.8",
            "installer:PHASE:Configuring the installation...",
            "installer:%percent:42.0"
        ],
        progress: 0.42
    )
    .frame(width: 520, height: 480)
}
