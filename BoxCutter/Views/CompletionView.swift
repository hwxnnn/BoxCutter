import SwiftUI

struct CompletionView: View {

    let success: Bool
    let packageName: String
    let message: String
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(success ? .green : .red)

            Text(success ? "Installation Complete" : "Installation Failed")
                .font(.title2.bold())

            Text(packageName)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !success {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .textSelection(.enabled)
            }

            Spacer()

            Button("Done") {
                onDone()
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
