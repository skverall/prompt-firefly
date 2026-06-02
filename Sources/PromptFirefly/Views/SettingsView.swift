import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var targetTracker = TargetAppTracker.shared

    @State private var draftAPIKey = ""
    @State private var saveMessage = ""
    @State private var saveState: SaveState = .idle

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    apiSection
                    endpointSection
                    folderSection
                    permissionSection
                    lastOperationSection
                }
                .padding(20)
            }

            Divider()

            footer
        }
        .frame(width: 680, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            draftAPIKey = settings.apiKey
            saveState = settings.apiKey.isEmpty ? .idle : .saved
            saveMessage = settings.apiKey.isEmpty ? "" : "API key loaded from Keychain."
            appState.refreshAccessibilityStatus()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            FireflyMark(status: appState.status)
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Prompt Firefly")
                        .font(.title3.weight(.semibold))

                    Text(AppVersion.badgeText)
                        .font(.caption.monospaced().weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }

                Text(statusLine)
                    .font(.callout)
                    .foregroundStyle(statusTint)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                appState.rewriteFocusedPrompt()
            } label: {
                Label("Rewrite", systemImage: "sparkles")
            }
            .keyboardShortcut("r", modifiers: [.command])

            Button {
                saveSettings()
            } label: {
                Label("Save", systemImage: "checkmark")
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var apiSection: some View {
        SettingsSection(title: "API Key", systemImage: "key.fill") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SecureField("Paste DeepSeek API key", text: $draftAPIKey)
                        .textFieldStyle(.roundedBorder)

                    saveBadge
                }

                if !saveMessage.isEmpty {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundStyle(saveState.tint)
                        .lineLimit(2)
                }
            }
        }
    }

    private var endpointSection: some View {
        SettingsSection(title: "Model", systemImage: "cpu.fill") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    SettingsLabel("Base URL")

                    TextField("https://api.deepseek.com", text: $settings.baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    SettingsLabel("Model")

                    TextField("deepseek-v4-flash", text: $settings.model)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var folderSection: some View {
        SettingsSection(title: "Context Folder", systemImage: "folder.fill") {
            HStack(spacing: 12) {
                Text(settings.projectFolder.isEmpty ? "Not selected" : settings.projectFolder)
                    .font(.callout.monospaced())
                    .foregroundStyle(settings.projectFolder.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Choose...") {
                    chooseProjectFolder()
                }
            }
        }
    }

    private var permissionSection: some View {
        SettingsSection(title: "Permissions", systemImage: "hand.raised.fill") {
            HStack(spacing: 12) {
                Label(
                    appState.accessibilityTrusted ? "Accessibility granted" : "Accessibility needed",
                    systemImage: appState.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(appState.accessibilityTrusted ? .green : .orange)

                Spacer()

                Button("Refresh") {
                    appState.refreshAccessibilityStatus()
                }

                Button("Request") {
                    appState.requestAccessibilityPermission()
                }

                Button("Open Settings") {
                    openAccessibilitySettings()
                }
            }
        }
    }

    private var lastOperationSection: some View {
        SettingsSection(title: "Last Operation", systemImage: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 10) {
                InfoRow(title: "Target", value: appState.lastTargetDescription.isEmpty ? "None yet" : appState.lastTargetDescription)
                InfoRow(title: "Text", value: appState.lastPromptPreview.isEmpty ? "No text captured yet" : appState.lastPromptPreview)

                HStack {
                    Spacer()

                    Button {
                        appState.testPromptCapture()
                    } label: {
                        Label("Test Capture", systemImage: "text.cursor")
                    }
                }

                if !appState.lastErrorMessage.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)

                        Text(appState.lastErrorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private var footer: some View {
            HStack {
                Text(footerStatus)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text("Cmd-R")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var footerStatus: String {
        let target = targetTracker.targetLabel
        let context = appState.currentContextLabel.isEmpty ? "Context: waiting" : appState.currentContextLabel
        return "\(AppVersion.displayText) • \(target) • \(context)"
    }

    private var saveBadge: some View {
        Label(saveState.label, systemImage: saveState.iconName)
            .font(.caption.weight(.medium))
            .foregroundStyle(saveState.tint)
            .frame(width: 96, alignment: .trailing)
    }

    private var statusLine: String {
        if case .error = appState.status {
            return appState.statusMessage
        }

        return appState.statusMessage
    }

    private var statusTint: Color {
        switch appState.status {
        case .idle:
            .secondary
        case .working:
            .blue
        case .success:
            .green
        case .error:
            .red
        }
    }

    private func saveSettings() {
        settings.apiKey = draftAPIKey

        do {
            try settings.saveAPIKey()
            draftAPIKey = settings.apiKey
            saveState = settings.apiKey.isEmpty ? .removed : .saved
            saveMessage = settings.apiKey.isEmpty ? "API key removed." : "API key saved and verified in Keychain."
            appState.statusMessage = saveMessage
        } catch {
            saveState = .failed
            saveMessage = error.localizedDescription
            showSaveError(error.localizedDescription)
        }
    }

    private func chooseProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the folder Prompt Firefly should use as coding context."

        if panel.runModal() == .OK, let url = panel.url {
            settings.projectFolder = url.path
            appState.currentContextLabel = "Context: \(url.lastPathComponent) (Settings)"
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func showSaveError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "API key was not saved"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35))
        )
    }
}

private struct SettingsLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(width: 84, alignment: .leading)
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                SettingsLabel(title)

                Text(value)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct FireflyMark: View {
    let status: FireflyStatus

    var body: some View {
        ZStack {
            Circle()
                .fill(gradient)
                .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))

            Image(systemName: iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var iconName: String {
        switch status {
        case .idle:
            "sparkles"
        case .working:
            "ellipsis"
        case .success:
            "checkmark"
        case .error:
            "exclamationmark"
        }
    }

    private var gradient: RadialGradient {
        switch status {
        case .idle:
            RadialGradient(colors: [.yellow, .green, .teal], center: .topLeading, startRadius: 2, endRadius: 44)
        case .working:
            RadialGradient(colors: [.cyan, .blue, .indigo], center: .topLeading, startRadius: 2, endRadius: 44)
        case .success:
            RadialGradient(colors: [.mint, .green, .teal], center: .topLeading, startRadius: 2, endRadius: 44)
        case .error:
            RadialGradient(colors: [.orange, .red, .pink], center: .topLeading, startRadius: 2, endRadius: 44)
        }
    }

    private var glowColor: Color {
        switch status {
        case .idle:
            .green
        case .working:
            .cyan
        case .success:
            .mint
        case .error:
            .orange
        }
    }
}

private enum SaveState {
    case idle
    case saved
    case removed
    case failed

    var label: String {
        switch self {
        case .idle:
            "Not saved"
        case .saved:
            "Saved"
        case .removed:
            "Removed"
        case .failed:
            "Error"
        }
    }

    var iconName: String {
        switch self {
        case .idle:
            "circle"
        case .saved:
            "checkmark.circle.fill"
        case .removed:
            "minus.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .idle:
            .secondary
        case .saved:
            .green
        case .removed:
            .orange
        case .failed:
            .red
        }
    }
}
