import SwiftUI

struct InstallingView: View {

    let packageName: String
    let outputLines: [String]
    @Binding var progress: Double
    @Binding var showDetails: Bool
    private let settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            // PINNED: Header + progress
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Installing \(packageName)\u{2026}")
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                }

                if settings.showProgressBar {
                    VStack(spacing: 4) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)

                        Text("\(Int(progress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
            .padding(16)

            // EXPANDABLE: Verbose log
            if showDetails && settings.showVerboseOutput {
                Divider()
                    .padding(.horizontal, 16)

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
                        .padding(8)
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

            // PINNED: Divider + details button
            Divider()
                .padding(.horizontal, 16)

            HStack {
                Button {
                    showDetails.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(showDetails ? 90 : 0))
                            .font(.caption2)
                        Text("Details")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .clipped()
    }
}

#Preview {
    InstallingView(
        packageName: "Example",
        outputLines: ["installer: Installing...", "installer:%50.0"],
        progress: .constant(0.5),
        showDetails: .constant(false)
    )
    .frame(width: 400)
}
