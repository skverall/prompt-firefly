import AppKit
import Foundation

enum TerminalCommandReader {
    static func currentCommand(in app: NSRunningApplication) -> String? {
        guard let script = appleScript(for: app) else { return nil }
        guard let screenText = runAppleScript(script) else { return nil }
        return TerminalCommandText.extractCommand(from: screenText)
    }

    private static func appleScript(for app: NSRunningApplication) -> String? {
        let name = app.localizedName?.lowercased() ?? ""
        let bundleID = app.bundleIdentifier?.lowercased() ?? ""

        if bundleID == "com.apple.terminal" || name == "terminal" {
            return """
            tell application "Terminal"
                if not (exists front window) then return ""
                return contents of selected tab of front window
            end tell
            """
        }

        if bundleID.contains("iterm") || name.contains("iterm") {
            return """
            tell application "iTerm2"
                if not (exists current window) then return ""
                return contents of current session of current window
            end tell
            """
        }

        return nil
    }

    private static func runAppleScript(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum TerminalCommandText {
    static func extractCommand(from text: String) -> String? {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { removeANSI(from: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let lastLine = lines.last else { return nil }
        guard !isPromptOnly(lastLine) else { return nil }

        let command = stripPromptPrefix(from: lastLine)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !command.isEmpty, command.count <= 2_000 else { return nil }
        return command
    }

    private static func stripPromptPrefix(from line: String) -> String {
        for marker in [" ❯ ", " ➜ ", " $ ", " % ", " # ", " > "] {
            if
                let range = line.range(of: marker, options: .backwards),
                line.distance(from: line.startIndex, to: range.lowerBound) <= 180
            {
                return String(line[range.upperBound...])
            }
        }

        for marker in ["❯ ", "➜ ", "$ ", "% ", "# ", "> "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }

        guard
            let regex = try? NSRegularExpression(pattern: #"[#$%❯➜>]\s+(.+)$"#),
            let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)),
            match.numberOfRanges == 2,
            match.range.location <= 180
        else {
            return line
        }

        return (line as NSString).substring(with: match.range(at: 1))
    }

    private static func isPromptOnly(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 220 else { return false }

        return trimmed == "$"
            || trimmed == "%"
            || trimmed == "#"
            || trimmed == ">"
            || trimmed == "❯"
            || trimmed == "➜"
            || trimmed.hasSuffix(" $")
            || trimmed.hasSuffix(" %")
            || trimmed.hasSuffix(" #")
            || trimmed.hasSuffix(" >")
            || trimmed.hasSuffix(" ❯")
            || trimmed.hasSuffix(" ➜")
    }

    private static func removeANSI(from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\u{001B}\[[0-?]*[ -/]*[@-~]"#) else {
            return text
        }

        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}
