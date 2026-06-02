import AppKit
import ApplicationServices
import Foundation

struct FocusedPrompt {
    let element: AXUIElement
    let processIdentifier: pid_t
    let text: String
    let fullValue: String?
    let selectedRange: CFRange?
    let appName: String
    let bundleIdentifier: String?
    let source: String
    let replacementStrategy: PromptReplacementStrategy
}

enum AccessibilityClient {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestPermissionPrompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func captureFocusedPrompt() throws -> FocusedPrompt {
        // Chromium/Electron apps only build their web accessibility tree once a
        // client asks for it via AXManualAccessibility. Prime the front app and
        // Codex-like apps so the first click has usable fields to inspect.
        enableManualAccessibilityForLikelyTargetApps()

        if
            let prompt = captureSystemFocusedPrompt(),
            prompt.processIdentifier != NSRunningApplication.current.processIdentifier,
            !shouldIgnoreFocusedPrompt(prompt)
        {
            return prompt
        }

        if let prompt = captureFrontmostAppPrompt() {
            return prompt
        }

        throw AccessibilityPromptError.noFocusedTextField
    }

    /// Asks Chromium/Electron apps (such as Codex) to expose their web
    /// accessibility tree. Without this their windows report no usable children
    /// and the prompt field can never be found. Safe to call repeatedly.
    static func enableManualAccessibility(for app: NSRunningApplication) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// Reads the current text value of a previously captured field. Used to verify
    /// that a rewrite actually landed. Returns nil if the value can't be read.
    static func currentValue(of prompt: FocusedPrompt) -> String? {
        stringAttribute(kAXValueAttribute, from: prompt.element)
    }

    private static func enableManualAccessibilityForLikelyTargetApps() {
        var apps: [NSRunningApplication] = []

        if let frontmost = NSWorkspace.shared.frontmostApplication {
            apps.append(frontmost)
        }

        apps.append(contentsOf: NSWorkspace.shared.runningApplications.filter(isCodexLikeApp))

        for app in apps where app.processIdentifier != NSRunningApplication.current.processIdentifier {
            enableManualAccessibility(for: app)
        }
    }

    static func replaceFocusedPrompt(_ prompt: FocusedPrompt, with rewrittenText: String) throws {
        focus(prompt)

        let newValue: String
        let cursorLocation: Int

        if
            let fullValue = prompt.fullValue,
            let selectedRange = prompt.selectedRange,
            selectedRange.length > 0
        {
            let fullNSString = fullValue as NSString
            let nsRange = NSRange(location: selectedRange.location, length: selectedRange.length)

            guard NSMaxRange(nsRange) <= fullNSString.length else {
                throw AccessibilityPromptError.cannotReplaceText
            }

            let mutable = NSMutableString(string: fullValue)
            mutable.replaceCharacters(in: nsRange, with: rewrittenText)
            newValue = mutable as String
            cursorLocation = selectedRange.location + (rewrittenText as NSString).length
        } else {
            newValue = rewrittenText
            cursorLocation = (rewrittenText as NSString).length
        }

        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(prompt.element, kAXValueAttribute as CFString, &settable)

        guard settable.boolValue else {
            throw AccessibilityPromptError.cannotReplaceText
        }

        let result = AXUIElementSetAttributeValue(
            prompt.element,
            kAXValueAttribute as CFString,
            newValue as CFTypeRef
        )

        guard result == .success else {
            throw AccessibilityPromptError.cannotReplaceText
        }

        var newRange = CFRange(location: cursorLocation, length: 0)
        if let axRange = AXValueCreate(.cfRange, &newRange) {
            AXUIElementSetAttributeValue(
                prompt.element,
                kAXSelectedTextRangeAttribute as CFString,
                axRange
            )
        }
    }

    static func focus(_ prompt: FocusedPrompt) {
        NSRunningApplication(processIdentifier: prompt.processIdentifier)?
            .activate(options: [.activateAllWindows])

        AXUIElementSetAttributeValue(
            prompt.element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
    }

    private static func captureSystemFocusedPrompt() -> FocusedPrompt? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )

        guard focusedResult == .success, let focusedValue else { return nil }
        let focusedElement = focusedValue as! AXUIElement
        let pid = processIdentifier(for: focusedElement)
        let app = NSRunningApplication(processIdentifier: pid)
        let appName = app?.localizedName ?? "front app"

        return promptCandidate(
            from: focusedElement,
            processIdentifier: pid,
            appName: appName,
            bundleIdentifier: app?.bundleIdentifier,
            source: "focused element"
        )?.prompt
    }

    private static func captureFrontmostAppPrompt() -> FocusedPrompt? {
        guard
            let app = NSWorkspace.shared.frontmostApplication,
            app.processIdentifier != NSRunningApplication.current.processIdentifier
        else {
            return nil
        }

        return capturePrompt(in: app)
    }

    private static func capturePrompt(in app: NSRunningApplication) -> FocusedPrompt? {
        // Chromium builds its accessibility tree asynchronously after
        // AXManualAccessibility is set, so retry briefly so the very first
        // click works instead of only succeeding on the second attempt.
        for attempt in 0..<6 {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)

            if let focusedPrompt = focusedPrompt(in: appElement, app: app) {
                return focusedPrompt
            }

            if let scannedPrompt = scannedPrompt(in: appElement, app: app) {
                return scannedPrompt
            }

            if attempt < 5 {
                usleep(120_000)
            }
        }

        return nil
    }

    private static func focusedPrompt(in appElement: AXUIElement, app: NSRunningApplication) -> FocusedPrompt? {
        var focusedValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )

        guard result == .success, let focusedValue else { return nil }
        let focusedElement = focusedValue as! AXUIElement

        return promptCandidate(
            from: focusedElement,
            processIdentifier: app.processIdentifier,
            appName: app.localizedName ?? "front app",
            bundleIdentifier: app.bundleIdentifier,
            source: "\(app.localizedName ?? "front app") focused field"
        )?.prompt
    }

    private static func scannedPrompt(in appElement: AXUIElement, app: NSRunningApplication) -> FocusedPrompt? {
        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
        guard result == .success, let windows = windowsValue as? [AXUIElement] else { return nil }

        var best: PromptCandidate?
        var visited = 0

        for window in windows.prefix(6) {
            scan(
                element: window,
                app: app,
                depth: 0,
                visited: &visited,
                best: &best
            )
        }

        return best?.prompt
    }

    private static func scan(
        element: AXUIElement,
        app: NSRunningApplication,
        depth: Int,
        visited: inout Int,
        best: inout PromptCandidate?
    ) {
        guard depth <= 7, visited < 420 else { return }
        visited += 1

        if let candidate = promptCandidate(
            from: element,
            processIdentifier: app.processIdentifier,
            appName: app.localizedName ?? "front app",
            bundleIdentifier: app.bundleIdentifier,
            source: "\(app.localizedName ?? "front app") window scan"
        ) {
            if best == nil || candidate.score > best!.score {
                best = candidate
            }
        }

        var childrenValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
        guard result == .success, let children = childrenValue as? [AXUIElement] else { return }

        for child in children.prefix(80) {
            scan(element: child, app: app, depth: depth + 1, visited: &visited, best: &best)
        }
    }

    private static func promptCandidate(
        from element: AXUIElement,
        processIdentifier: pid_t,
        appName: String,
        bundleIdentifier: String?,
        source: String
    ) -> PromptCandidate? {
        let selectedText = stringAttribute(kAXSelectedTextAttribute, from: element)
        let fullValue = stringAttribute(kAXValueAttribute, from: element)
        let selectedRange = selectedRange(from: element)
        let rawText = selectedText?.isEmpty == false ? selectedText! : (fullValue ?? "")
        let targetKind = TargetAppKind.detect(appName: appName, bundleIdentifier: bundleIdentifier)
        let replacementStrategy: PromptReplacementStrategy = targetKind == .terminal ? .terminalCommandLine : .accessibilityValue
        let text = targetKind == .terminal ? (TerminalCommandText.extractCommand(from: rawText) ?? rawText) : rawText
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return nil }

        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)

        let role = stringAttribute(kAXRoleAttribute, from: element) ?? ""
        let editable = boolAttribute("AXEditable", from: element) ?? false
        let isTextLike = role == (kAXTextAreaRole as String) || role == (kAXTextFieldRole as String)
        let hasSelection = selectedRange?.length ?? 0 > 0

        guard isTextLike || editable || settable.boolValue || hasSelection else { return nil }

        let metadata = [
            stringAttribute(kAXTitleAttribute, from: element),
            stringAttribute(kAXDescriptionAttribute, from: element),
            stringAttribute(kAXHelpAttribute, from: element)
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        guard !isMisleadingPathCandidate(trimmed, metadata: metadata) else { return nil }

        var score = 0
        if settable.boolValue { score += 80 }
        if editable { score += 60 }
        if role == (kAXTextAreaRole as String) { score += 35 }
        if role == (kAXTextFieldRole as String) { score += 20 }
        if hasSelection { score += 25 }
        if trimmed.count < 20_000 { score += 8 }

        if metadata.contains("prompt") || metadata.contains("message") || metadata.contains("input") {
            score += 25
        }

        if targetKind == .terminal {
            score += 30
        }

        return PromptCandidate(
            prompt: FocusedPrompt(
                element: element,
                processIdentifier: processIdentifier,
                text: text,
                fullValue: fullValue,
                selectedRange: selectedRange,
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                source: source,
                replacementStrategy: replacementStrategy
            ),
            score: score
        )
    }

    private static func isCodexLikeApp(_ app: NSRunningApplication) -> Bool {
        let name = app.localizedName?.lowercased() ?? ""
        let bundleID = app.bundleIdentifier?.lowercased() ?? ""
        guard !name.contains("computer use") && !bundleID.contains("computer-use") else { return false }
        return name.contains("codex") || bundleID.contains("codex")
    }

    private static func shouldIgnoreFocusedPrompt(_ prompt: FocusedPrompt) -> Bool {
        isStandaloneLocalPath(prompt.text)
    }

    private static func processIdentifier(for element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    private static func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private static func boolAttribute(_ attribute: String, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? Bool
    }

    private static func selectedRange(from element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )

        guard result == .success, let axValue = value else { return nil }

        var range = CFRange()
        guard AXValueGetValue(axValue as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    private static func isMisleadingPathCandidate(_ text: String, metadata: String) -> Bool {
        if isInternalToolPath(text) {
            return true
        }

        guard isStandaloneLocalPath(text) else { return false }

        let userTextHints = ["prompt", "message", "composer", "input", "text area", "textarea"]
        return !userTextHints.contains { metadata.contains($0) }
    }

    private static func isStandaloneLocalPath(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 600 else { return false }
        guard !trimmed.contains("\n") else { return false }
        guard trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") else { return false }

        let expandedPath: String
        if trimmed.hasPrefix("~/") {
            expandedPath = NSHomeDirectory() + String(trimmed.dropFirst())
        } else {
            expandedPath = trimmed
        }

        let cleaned = expandedPath.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:'\"`)]}"))
        guard cleaned.hasPrefix("/") else { return false }

        if isInternalToolPath(cleaned) {
            return true
        }

        return FileManager.default.fileExists(atPath: cleaned)
    }

    private static func isInternalToolPath(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("/.codex/plugins/")
            || lowercased.contains("/.codex/plugins/cache/")
            || lowercased.contains("/.codex/skills/.system/")
            || lowercased.contains("/plugins/cache/")
            || lowercased.contains("/node_modules/")
            || lowercased.contains("/deriveddata/")
            || lowercased.contains("/library/caches/")
            || lowercased.contains("/.build/")
    }
}

private struct PromptCandidate {
    let prompt: FocusedPrompt
    let score: Int
}

enum AccessibilityPromptError: LocalizedError {
    case noFocusedTextField
    case cannotReplaceText

    var errorDescription: String? {
        switch self {
        case .noFocusedTextField:
            "Focused text field was not found"
        case .cannotReplaceText:
            "Cannot replace text in the focused field"
        }
    }
}
