import Foundation

enum TargetAppKind: String, Equatable {
    case codingAssistant = "AI coding assistant"
    case terminal = "terminal"
    case codeEditor = "code editor"
    case messaging = "messaging app"
    case browser = "browser"
    case general = "general app"

    static func detect(appName: String, bundleIdentifier: String?) -> TargetAppKind {
        let name = appName.lowercased()
        let bundleID = bundleIdentifier?.lowercased() ?? ""
        let haystack = "\(name) \(bundleID)"

        if haystack.contains("computer-use") || haystack.contains("computer use") {
            return .general
        }

        if haystack.containsAny(["codex", "chatgpt", "claude"]) {
            return .codingAssistant
        }

        if haystack.containsAny([
            "terminal",
            "iterm",
            "warp",
            "ghostty",
            "wezterm",
            "alacritty",
            "kitty",
            "hyper"
        ]) {
            return .terminal
        }

        if haystack.containsAny([
            "visual studio code",
            "vscode",
            "cursor",
            "xcode",
            "zed",
            "sublime",
            "intellij",
            "pycharm",
            "webstorm",
            "android studio"
        ]) {
            return .codeEditor
        }

        if haystack.containsAny([
            "telegram",
            "whatsapp",
            "messages",
            "signal",
            "slack",
            "discord",
            "mail",
            "spark",
            "superhuman"
        ]) {
            return .messaging
        }

        if haystack.containsAny([
            "safari",
            "chrome",
            "firefox",
            "arc",
            "brave",
            "edge",
            "browser"
        ]) {
            return .browser
        }

        return .general
    }

    var allowsProjectContext: Bool {
        switch self {
        case .codingAssistant, .terminal, .codeEditor:
            true
        case .messaging, .browser, .general:
            false
        }
    }
}

enum PromptReplacementStrategy: Equatable {
    case accessibilityValue
    case keyboardSelection
    case terminalCommandLine
}

private extension String {
    func containsAny(_ needles: [String]) -> Bool {
        needles.contains { contains($0) }
    }
}
