import SwiftUI

struct InstallingView: View {

    let packageName: String
    let outputLines: [String]
    let progress: Double

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

            // Progress bar
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
