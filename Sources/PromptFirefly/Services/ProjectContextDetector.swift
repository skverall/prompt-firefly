import AppKit
import ApplicationServices
import Foundation

struct ProjectContext {
    let folderPath: String?
    let folderName: String
    let source: String
    let summary: String

    var shortLabel: String {
        guard folderPath != nil else { return "Context: none" }
        return "Context: \(folderName) (\(source))"
    }
}

enum ProjectContextDetector {
    static func detect(
        preferredFolder: String,
        targetKind: TargetAppKind,
        targetAppName: String
    ) -> ProjectContext {
        guard targetKind.allowsProjectContext else {
            return noContext(
                "No local project context was used for \(targetAppName). Rewrite only the text from the focused app."
            )
        }

        let detectedFolder = detectFolderForTarget(targetKind: targetKind, targetAppName: targetAppName)
        let candidates: [(folder: String?, source: String, detected: Bool)] = [
            (detectedFolder, targetAppName, true),
            (preferredFolder.nilIfBlank, "Settings", false)
        ]

        for (candidate, source, detected) in candidates {
            guard let candidate else { continue }
            guard FileManager.default.isDirectory(atPath: candidate) else { continue }

            if detected, !isUsefulDetectedFolder(candidate) {
                continue
            }

            return context(for: candidate, source: source)
        }

        return noContext("Project folder was not detected. Rewrite without local project files.")
    }

    private static func noContext(_ summary: String) -> ProjectContext {
        ProjectContext(
            folderPath: nil,
            folderName: "No folder",
            source: "None",
            summary: summary
        )
    }

    private static func detectFolderForTarget(targetKind: TargetAppKind, targetAppName: String) -> String? {
        let lowercasedName = targetAppName.lowercased()

        if targetKind == .codingAssistant, lowercasedName.contains("codex") {
            if let folder = detectCodexFolderFromAccessibility() {
                return folder
            }
        }

        if
            let frontmost = NSWorkspace.shared.frontmostApplication,
            (frontmost.localizedName ?? "").caseInsensitiveCompare(targetAppName) == .orderedSame
        {
            let appElement = AXUIElementCreateApplication(frontmost.processIdentifier)
            let collectedText = collectWindowText(from: appElement).joined(separator: "\n")
            return firstExistingFolder(in: collectedText)
        }

        return nil
    }

    private static func detectCodexFolderFromAccessibility() -> String? {
        let codexApps = NSWorkspace.shared.runningApplications.filter { app in
            let name = app.localizedName?.lowercased() ?? ""
            let bundleID = app.bundleIdentifier?.lowercased() ?? ""
            guard !name.contains("computer use") && !bundleID.contains("computer-use") else { return false }
            return name.contains("codex") || bundleID.contains("codex")
        }

        for app in codexApps {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            let collectedText = collectWindowText(from: appElement).joined(separator: "\n")
            if let path = firstExistingFolder(in: collectedText) {
                return path
            }
        }

        return nil
    }

    private static func collectWindowText(from appElement: AXUIElement) -> [String] {
        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
        guard result == .success, let windows = windowsValue as? [AXUIElement] else { return [] }

        var values: [String] = []
        for window in windows.prefix(5) {
            values.append(contentsOf: collectText(from: window, depth: 0, maxDepth: 2, limit: 80))
        }
        return values
    }

    private static func collectText(from element: AXUIElement, depth: Int, maxDepth: Int, limit: Int) -> [String] {
        guard depth <= maxDepth else { return [] }

        var values: [String] = []
        for attribute in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute, kAXHelpAttribute] {
            guard values.count < limit else { break }
            if let value = stringAttribute(attribute, from: element), !value.isEmpty {
                values.append(value)
            }
        }

        guard depth < maxDepth, values.count < limit else { return values }

        var childrenValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
        guard result == .success, let children = childrenValue as? [AXUIElement] else { return values }

        for child in children.prefix(30) where values.count < limit {
            values.append(contentsOf: collectText(from: child, depth: depth + 1, maxDepth: maxDepth, limit: limit - values.count))
        }

        return values
    }

    private static func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private static func firstExistingFolder(in text: String) -> String? {
        let pattern = #"/Users/[^\n\r\"'<>()\]]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            var path = nsText.substring(with: match.range)
            path = cleanPathCandidate(path)

            if FileManager.default.isDirectory(atPath: path) {
                if isUsefulDetectedFolder(path) {
                    return path
                }
                continue
            }

            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue {
                let folder = (path as NSString).deletingLastPathComponent
                if isUsefulDetectedFolder(folder) {
                    return folder
                }
                continue
            }
        }

        return nil
    }

    private static func cleanPathCandidate(_ path: String) -> String {
        var cleaned = path.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:'\"`)]}"))

        while cleaned.hasSuffix("/") {
            cleaned.removeLast()
        }

        return cleaned
    }

    private static func isUsefulDetectedFolder(_ folder: String) -> Bool {
        let lowercased = folder.lowercased()

        if lowercased.contains("/.codex/plugins/")
            || lowercased.contains("/.codex/plugins/cache/")
            || lowercased.contains("/.codex/skills/.system/")
            || lowercased.contains("/plugins/cache/")
            || lowercased.contains("/node_modules/")
            || lowercased.contains("/deriveddata/")
            || lowercased.contains("/library/caches/")
            || lowercased.contains("/.build/")
        {
            return false
        }

        return true
    }

    private static func context(for folder: String, source: String) -> ProjectContext {
        let folderURL = URL(fileURLWithPath: folder)
        let folderName = folderURL.lastPathComponent
        let topLevelFiles = topLevelFileList(folderURL: folderURL)
        let agents = readFileIfExists(folderURL.appendingPathComponent("AGENTS.md"), limit: 2_400)
        let readme = firstReadableFile(
            in: folderURL,
            names: ["README.md", "README.txt", "readme.md"],
            limit: 1_800
        )
        let gitStatus = gitStatus(folder: folder)

        var parts: [String] = [
            "Project folder: \(folderName)",
            "Path: \(folder)",
            "Context source: \(source)",
            "Top-level files:\n\(topLevelFiles)"
        ]

        if let agents {
            parts.append("AGENTS.md:\n\(agents)")
        }

        if let readme {
            parts.append("README:\n\(readme)")
        }

        if let gitStatus, !gitStatus.isEmpty {
            parts.append("Git status:\n\(gitStatus)")
        }

        return ProjectContext(
            folderPath: folder,
            folderName: folderName,
            source: source,
            summary: parts.joined(separator: "\n\n")
        )
    }

    private static func topLevelFileList(folderURL: URL) -> String {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return "Could not read folder contents."
        }

        return urls
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(80)
            .map { url in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return "\(isDirectory ? "[dir]" : "[file]") \(url.lastPathComponent)"
            }
            .joined(separator: "\n")
    }

    private static func readFileIfExists(_ url: URL, limit: Int) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard var text = String(data: data, encoding: .utf8) else { return nil }

        if text.count > limit {
            text = String(text.prefix(limit)) + "\n..."
        }

        return text
    }

    private static func firstReadableFile(in folderURL: URL, names: [String], limit: Int) -> String? {
        for name in names {
            if let text = readFileIfExists(folderURL.appendingPathComponent(name), limit: limit) {
                return text
            }
        }
        return nil
    }

    private static func gitStatus(folder: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", folder, "status", "--short"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension FileManager {
    func isDirectory(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
