import SwiftUI

struct CompletionView: View {

    let success: Bool
    let packageName: String
    let message: String
    let onDone: () -> Void
    var extraActions: [CompletionAction] = []

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

            if !extraActions.isEmpty {
                Divider()
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                HStack(spacing: 8) {
                    Spacer()
                    ForEach(extraActions) { action in
                        Button(action.label) { action.handler() }
                    }
                    Button("Done") { onDone() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 10)
            } else {
                HStack {
                    Spacer()
                    Button("Done") { onDone() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 10)
            }
        }
        .padding(16)
    }
}

struct CompletionAction: Identifiable {
    let id = UUID()
    let label: String
    let handler: () -> Void

    static func == (lhs: CompletionAction, rhs: CompletionAction) -> Bool {
        lhs.id == rhs.id
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

#Preview("DMG Complete") {
    CompletionView(
        success: true,
        packageName: "MyApp",
        message: "",
        onDone: {},
        extraActions: [
            CompletionAction(label: "Show in Finder") {},
            CompletionAction(label: "Open App") {}
        ]
    )
    .frame(width: 400)
}
