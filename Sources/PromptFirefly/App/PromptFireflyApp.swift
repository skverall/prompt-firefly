import SwiftUI

@main
struct PromptFireflyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let appState = AppState.shared

    var body: some Scene {
        MenuBarExtra("Prompt Firefly", systemImage: "sparkles") {
            MenuBarView(appState: appState)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Button("Rewrite focused text") {
            appState.rewriteFocusedPrompt()
        }

        Button("Undo last rewrite") {
            appState.undoLastRewrite()
        }
        .disabled(!appState.canUndo)

        Button("Settings") {
            NotificationCenter.default.post(name: .promptFireflyShowSettings, object: nil)
        }

        if !appState.currentContextLabel.isEmpty {
            Divider()
            Text(appState.currentContextLabel)
                .lineLimit(1)
        }

        Divider()

        Text(AppVersion.displayText)

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}
