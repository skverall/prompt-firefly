import Foundation

enum FireflyStatus: Equatable {
    case idle
    case working
    case success
    case error(String)
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let settings = SettingsStore.shared

    @Published var status: FireflyStatus = .idle
    @Published var statusMessage = "Ready"
    @Published var accessibilityTrusted = false
    @Published var currentContextLabel = ""
    @Published var lastRewrite = ""
    @Published var lastTargetDescription = ""
    @Published var lastPromptPreview = ""
    @Published var lastErrorMessage = ""
    @Published var canUndo = false

    private var resetStatusTask: Task<Void, Never>?
    private var lastCapture: PromptCapture?
    private var lastOriginalText: String?

    private init() {}

    func loadDefaultProjectFolderIfNeeded() {
        guard settings.projectFolder.isEmpty else { return }
        guard let resourceURL = Bundle.main.url(forResource: "default-context", withExtension: "txt") else { return }
        guard let path = try? String(contentsOf: resourceURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        guard FileManager.default.isDirectory(atPath: path) else { return }

        settings.projectFolder = path
    }

    func refreshAccessibilityStatus() {
        accessibilityTrusted = AccessibilityClient.isTrusted()
    }

    func requestAccessibilityPermission() {
        AccessibilityClient.requestPermissionPrompt()
        refreshAccessibilityStatus()
    }

    func rewriteFocusedPrompt() {
        guard status != .working else { return }

        Task {
            await rewriteFocusedPromptNow()
        }
    }

    func undoLastRewrite() {
        guard status != .working else { return }
        guard let capture = lastCapture, let original = lastOriginalText else { return }

        Task {
            do {
                setStatus(.working)
                // Whole-field restore: select all and paste the original text back.
                // This reverts both full and partial rewrites.
                try capture.replaceUsingPaste(with: original)

                lastRewrite = original
                lastErrorMessage = ""
                canUndo = false
                lastCapture = nil
                lastOriginalText = nil
                statusMessage = "Reverted to original"
                setStatus(.success)
            } catch {
                setStatus(.error(error.localizedDescription))
            }
        }
    }

    func testPromptCapture() {
        guard status != .working else { return }

        Task {
            refreshAccessibilityStatus()

            guard accessibilityTrusted else {
                setStatus(.error("Accessibility permission is needed"))
                return
            }

            do {
                let capturedPrompt = try capturePrompt()
                let text = capturedPrompt.text.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !text.isEmpty else {
                    throw PromptFireflyError.emptyPrompt
                }

                lastTargetDescription = "\(capturedPrompt.appName) (\(capturedPrompt.targetKind.rawValue)) • \(capturedPrompt.source)"
                lastPromptPreview = Self.preview(text)
                lastErrorMessage = ""
                statusMessage = "Captured from \(capturedPrompt.appName)"
                setStatus(.success)
            } catch {
                setStatus(.error(error.localizedDescription))
            }
        }
    }

    private func rewriteFocusedPromptNow() async {
        refreshAccessibilityStatus()

        guard accessibilityTrusted else {
            setStatus(.error("Accessibility permission is needed"))
            return
        }

        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            setStatus(.error("Add API key in Settings"))
            NotificationCenter.default.post(name: .promptFireflyShowSettings, object: nil)
            return
        }

        do {
            setStatus(.working)

            let capturedPrompt = try capturePrompt()
            let originalText = capturedPrompt.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let originalFullText = capturedPrompt.fullText

            guard !originalText.isEmpty else {
                throw PromptFireflyError.emptyPrompt
            }

            let targetKind = capturedPrompt.targetKind
            lastTargetDescription = "\(capturedPrompt.appName) (\(targetKind.rawValue)) • \(capturedPrompt.source)"
            lastPromptPreview = Self.preview(originalText)

            let context = ProjectContextDetector.detect(
                preferredFolder: settings.projectFolder,
                targetKind: targetKind,
                targetAppName: capturedPrompt.appName
            )
            currentContextLabel = context.shortLabel

            let snapshot = settings.snapshot(apiKey: apiKey)
            let rewritten = try await PromptRewriteService.rewrite(
                originalPrompt: originalText,
                projectContext: context,
                targetKind: targetKind,
                targetAppName: capturedPrompt.appName,
                captureSource: capturedPrompt.source,
                settings: snapshot
            )

            do {
                try capturedPrompt.replace(with: rewritten)
                statusMessage = "Rewritten in \(capturedPrompt.appName)"
            } catch {
                try capturedPrompt.replaceUsingPaste(with: rewritten)
                statusMessage = "Rewritten via paste"
            }

            // Confirm the field actually changed. Chromium/Electron apps can silently
            // ignore an AX write, and a mis-focused paste lands nowhere.
            try? await Task.sleep(nanoseconds: 150_000_000)
            if
                capturedPrompt.canVerifyFieldValue,
                !originalFullText.isEmpty,
                let current = capturedPrompt.currentFieldValue()?.trimmingCharacters(in: .whitespacesAndNewlines),
                current == originalFullText.trimmingCharacters(in: .whitespacesAndNewlines)
            {
                throw PromptFireflyError.writeNotApplied
            }

            lastRewrite = rewritten
            lastErrorMessage = ""
            lastCapture = capturedPrompt
            lastOriginalText = originalFullText
            canUndo = true
            setStatus(.success)
        } catch {
            setStatus(.error(error.localizedDescription))
        }
    }

    private func setStatus(_ newStatus: FireflyStatus) {
        resetStatusTask?.cancel()
        status = newStatus

        switch newStatus {
        case .idle:
            statusMessage = "Ready"
        case .working:
            statusMessage = "Rewriting..."
        case .success:
            break
        case .error(let message):
            statusMessage = message
            lastErrorMessage = message
        }

        // Auto-dismiss success only. Errors stay until the next action so the user
        // can actually read them.
        guard newStatus == .success else { return }

        resetStatusTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                self?.status = .idle
                self?.statusMessage = "Ready"
            }
        }
    }

    private func capturePrompt() throws -> PromptCapture {
        do {
            return .accessibility(try AccessibilityClient.captureFocusedPrompt())
        } catch {
            let app = TargetAppTracker.shared.preferredTargetApp()
            return .keyboard(try KeyboardPaster.captureFocusedText(from: app))
        }
    }

    private static func preview(_ text: String) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if singleLine.count <= 160 {
            return singleLine
        }

        return String(singleLine.prefix(160)) + "..."
    }
}

private enum PromptCapture {
    case accessibility(FocusedPrompt)
    case keyboard(KeyboardPrompt)

    var text: String {
        switch self {
        case .accessibility(let prompt):
            prompt.text
        case .keyboard(let prompt):
            prompt.text
        }
    }

    var fullText: String {
        switch self {
        case .accessibility(let prompt):
            if prompt.replacementStrategy == .terminalCommandLine {
                return prompt.text
            }
            return prompt.fullValue ?? prompt.text
        case .keyboard(let prompt):
            return prompt.text
        }
    }

    /// The field's value right now, if it can be read back (accessibility path only).
    func currentFieldValue() -> String? {
        switch self {
        case .accessibility(let prompt):
            return AccessibilityClient.currentValue(of: prompt)
        case .keyboard:
            return nil
        }
    }

    var appName: String {
        switch self {
        case .accessibility(let prompt):
            prompt.appName
        case .keyboard(let prompt):
            prompt.appName
        }
    }

    var bundleIdentifier: String? {
        switch self {
        case .accessibility(let prompt):
            prompt.bundleIdentifier
        case .keyboard(let prompt):
            prompt.bundleIdentifier
        }
    }

    var targetKind: TargetAppKind {
        TargetAppKind.detect(appName: appName, bundleIdentifier: bundleIdentifier)
    }

    var source: String {
        switch self {
        case .accessibility(let prompt):
            prompt.source
        case .keyboard(let prompt):
            prompt.source
        }
    }

    var replacementStrategy: PromptReplacementStrategy {
        switch self {
        case .accessibility(let prompt):
            prompt.replacementStrategy
        case .keyboard(let prompt):
            prompt.replacementStrategy
        }
    }

    var canVerifyFieldValue: Bool {
        replacementStrategy == .accessibilityValue
    }

    func replace(with text: String) throws {
        switch self {
        case .accessibility(let prompt):
            if prompt.replacementStrategy == .accessibilityValue {
                try AccessibilityClient.replaceFocusedPrompt(prompt, with: text)
            } else {
                try KeyboardPaster.replaceText(in: prompt, with: text)
            }
        case .keyboard(let prompt):
            try KeyboardPaster.replaceText(in: prompt, with: text)
        }
    }

    func replaceUsingPaste(with text: String) throws {
        switch self {
        case .accessibility(let prompt):
            try KeyboardPaster.replaceText(in: prompt, with: text)
        case .keyboard(let prompt):
            try KeyboardPaster.replaceText(in: prompt, with: text)
        }
    }
}

enum PromptFireflyError: LocalizedError {
    case emptyPrompt
    case writeNotApplied

    var errorDescription: String? {
        switch self {
        case .emptyPrompt:
            "Focused text is empty"
        case .writeNotApplied:
            "Could not write into the focused app. Click inside the text field and try again."
        }
    }
}
