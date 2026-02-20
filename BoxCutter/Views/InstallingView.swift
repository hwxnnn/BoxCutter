import SwiftUI

struct InstallingView: View {

    let packageName: String
    let outputLines: [String]
    let progress: Double
    @Binding var showDetails: Bool
    private let settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            // Compact header + progress
            VStack(spacing: 8) {
                HStack {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Installing \(packageName)\u{2026}")
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                }

                if settings.showProgressBar {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)

                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Details toggle
            if showDetails && settings.showVerboseOutput {
                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(outputLines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                    .id(index)
                            }
                        }
                        .padding(6)
                    }
                    .background(.background.secondary)
                    .frame(maxHeight: 260)
                    .onChange(of: outputLines.count) { _, _ in
                        if let last = outputLines.indices.last {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Details button
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDetails.toggle()
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }
}

#Preview {
    InstallingView(
        packageName: "Example",
        outputLines: ["installer: Installing...", "installer:%50.0"],
        progress: 0.5,
        showDetails: .constant(false)
    )
    .frame(width: 360)
}
