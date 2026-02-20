import SwiftUI

struct CompletionView: View {

    let success: Bool
    let packageName: String
    let message: String
    let onDone: () -> Void

    var body: some View {
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

            Button("Done") { onDone() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }
}

#Preview("Success") {
    CompletionView(success: true, packageName: "Example", message: "", onDone: {})
        .frame(width: 400)
}

#Preview("Failure") {
    CompletionView(success: false, packageName: "Example", message: "Exit code 1.", onDone: {})
        .frame(width: 400)
}
