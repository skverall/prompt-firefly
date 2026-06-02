import AppKit
import Foundation

struct KeyboardPrompt {
    let processIdentifier: pid_t
    let appName: String
    let bundleIdentifier: String?
    let text: String
    let previousClipboard: String?
    let source: String
    let replacementStrategy: PromptReplacementStrategy
}

enum KeyboardPaster {
    static func captureFocusedText(from app: NSRunningApplication?) throws -> KeyboardPrompt {
        guard let app else {
            throw KeyboardPromptError.noTargetApp
        }

        let appName = app.localizedName ?? "target app"
        let kind = TargetAppKind.detect(appName: appName, bundleIdentifier: app.bundleIdentifier)

        if kind == .terminal {
            guard let command = TerminalCommandReader.currentCommand(in: app) else {
                throw KeyboardPromptError.emptyCopy(appName)
            }

            return KeyboardPrompt(
                processIdentifier: app.processIdentifier,
                appName: appName,
                bundleIdentifier: app.bundleIdentifier,
                text: command,
                previousClipboard: NSPasteboard.general.string(forType: .string),
                source: "terminal command line",
                replacementStrategy: .terminalCommandLine
            )
        }

        let pasteboard = NSPasteboard.general
        let previousClipboard = pasteboard.string(forType: .string)
        let marker = "PROMPT_FIREFLY_MARKER_\(UUID().uuidString)"

        pasteboard.clearContents()
        pasteboard.setString(marker, forType: .string)

        app.activate(options: [.activateAllWindows])
        usleep(260_000)

        sendKey(keyCode: 0, flags: .maskCommand)
        usleep(90_000)
        sendKey(keyCode: 8, flags: .maskCommand)

        let copiedText = waitForCopiedText(marker: marker)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        restoreClipboard(previousClipboard)

        guard !copiedText.isEmpty else {
            throw KeyboardPromptError.emptyCopy(appName)
        }

        return KeyboardPrompt(
            processIdentifier: app.processIdentifier,
            appName: appName,
            bundleIdentifier: app.bundleIdentifier,
            text: copiedText,
            previousClipboard: previousClipboard,
            source: "keyboard copy fallback",
            replacementStrategy: .keyboardSelection
        )
    }

    static func replaceFocusedText(with text: String) throws {
        let pasteboard = NSPasteboard.general
        let previousClipboard = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        sendKey(keyCode: 0, flags: .maskCommand)
        usleep(120_000)
        sendKey(keyCode: 9, flags: .maskCommand)
        usleep(160_000)                            // let the paste land first

        restoreClipboard(previousClipboard)
    }

    static func replaceText(in prompt: FocusedPrompt, with text: String) throws {
        if prompt.replacementStrategy == .terminalCommandLine {
            try replaceTerminalCommandLine(processIdentifier: prompt.processIdentifier, with: text)
            return
        }

        AccessibilityClient.focus(prompt)
        usleep(220_000)
        try replaceFocusedText(with: text)
    }

    static func replaceText(in prompt: KeyboardPrompt, with text: String) throws {
        if prompt.replacementStrategy == .terminalCommandLine {
            try replaceTerminalCommandLine(processIdentifier: prompt.processIdentifier, with: text)
            return
        }

        guard let app = NSRunningApplication(processIdentifier: prompt.processIdentifier) else {
            throw KeyboardPromptError.noTargetApp
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        app.activate(options: [.activateAllWindows])
        usleep(260_000)

        sendKey(keyCode: 0, flags: .maskCommand)
        usleep(90_000)
        sendKey(keyCode: 9, flags: .maskCommand)
        usleep(180_000)

        restoreClipboard(prompt.previousClipboard)
    }

    private static func replaceTerminalCommandLine(processIdentifier: pid_t, with text: String) throws {
        guard let app = NSRunningApplication(processIdentifier: processIdentifier) else {
            throw KeyboardPromptError.noTargetApp
        }

        let pasteboard = NSPasteboard.general
        let previousClipboard = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        app.activate(options: [.activateAllWindows])
        usleep(220_000)

        sendKey(keyCode: 0, flags: .maskControl)     // Ctrl+A: start of command line
        usleep(80_000)
        sendKey(keyCode: 40, flags: .maskControl)    // Ctrl+K: clear to end of line
        usleep(100_000)
        sendKey(keyCode: 9, flags: .maskCommand)     // Cmd+V: paste corrected command
        usleep(160_000)

        restoreClipboard(previousClipboard)
    }

    private static func waitForCopiedText(marker: String) -> String {
        let pasteboard = NSPasteboard.general

        for _ in 0..<18 {
            usleep(70_000)
            let text = pasteboard.string(forType: .string) ?? ""
            if text != marker {
                return text
            }
        }

        return ""
    }

    private static func restoreClipboard(_ text: String?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let text {
            pasteboard.setString(text, forType: .string)
        }
    }

    private static func sendKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = flags
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = flags
        keyUp?.post(tap: .cghidEventTap)
    }
}

enum KeyboardPromptError: LocalizedError {
    case noTargetApp
    case emptyCopy(String)

    var errorDescription: String? {
        switch self {
        case .noTargetApp:
            "Target app was not found"
        case .emptyCopy(let appName):
            "Could not copy text from \(appName). Click inside the text field and try again."
        }
    }
}
