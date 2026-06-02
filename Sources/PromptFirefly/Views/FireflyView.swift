import SwiftUI

struct FireflyView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundGradient)
                .frame(width: 56, height: 56)
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.72), lineWidth: 1.2)
                )

            statusIcon
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.24), radius: 2, x: 0, y: 1)
        }
        .frame(width: 74, height: 74)
        .background(Color.clear)
        .contentShape(Circle())
        .contextMenu {
            Button("Rewrite") {
                appState.rewriteFocusedPrompt()
            }

            Button("Undo last rewrite") {
                appState.undoLastRewrite()
            }
            .disabled(!appState.canUndo)

            Button("Settings") {
                NotificationCenter.default.post(name: .promptFireflyShowSettings, object: nil)
            }
        }
        .help(appState.statusMessage)
    }

    private var statusIcon: some View {
        Group {
            switch appState.status {
            case .idle:
                Image(systemName: "sparkles")
            case .working:
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            case .success:
                Image(systemName: "checkmark")
            case .error:
                Image(systemName: "exclamationmark")
            }
        }
    }

    private var backgroundGradient: RadialGradient {
        switch appState.status {
        case .idle:
            RadialGradient(colors: [.yellow, .green, .teal], center: .topLeading, startRadius: 4, endRadius: 58)
        case .working:
            RadialGradient(colors: [.cyan, .blue, .indigo], center: .topLeading, startRadius: 4, endRadius: 58)
        case .success:
            RadialGradient(colors: [.mint, .green, .teal], center: .topLeading, startRadius: 4, endRadius: 58)
        case .error:
            RadialGradient(colors: [.orange, .red, .pink], center: .topLeading, startRadius: 4, endRadius: 58)
        }
    }
}
