import SwiftUI

/// A native sheet keeps the requested order; system alerts reorder default buttons.
struct UniversalThinningPrompt: View {
    let message: String
    let onChoose: (UniversalStripChoice) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image("UniversalThinningIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)

            Text("Thin Universal apps")
                .font(.headline)

            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                Button { onChoose(.no) } label: {
                    Text("No").frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.cancelAction)

                Button { onChoose(.yes) } label: {
                    Text("Yes").frame(maxWidth: .infinity)
                }

                Button { onChoose(.always) } label: {
                    Text("Always").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .keyboardShortcut(.defaultAction)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .frame(width: 300)
        .padding(24)
        .interactiveDismissDisabled()
    }
}
