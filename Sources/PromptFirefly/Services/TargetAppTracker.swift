import AppKit
import Foundation

@MainActor
final class TargetAppTracker: ObservableObject {
    static let shared = TargetAppTracker()

    @Published private(set) var targetLabel = "Target: waiting for app"

    private var observer: NSObjectProtocol?
    private var lastTargetProcessIdentifier: pid_t?

    private init() {}

    func start() {
        update(with: NSWorkspace.shared.frontmostApplication)

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }

            Task { @MainActor in
                self?.update(with: app)
            }
        }
    }

    func preferredTargetApp() -> NSRunningApplication? {
        if
            let pid = lastTargetProcessIdentifier,
            let app = NSRunningApplication(processIdentifier: pid),
            app.isTerminated == false
        {
            return app
        }

        if let frontmost = NSWorkspace.shared.frontmostApplication, isUsableTargetApp(frontmost) {
            update(with: frontmost)
            return frontmost
        }

        return nil
    }

    private func update(with app: NSRunningApplication?) {
        guard let app else { return }
        guard app.processIdentifier != NSRunningApplication.current.processIdentifier else { return }
        guard isUsableTargetApp(app) else { return }

        lastTargetProcessIdentifier = app.processIdentifier
        let appName = app.localizedName ?? "app"
        let kind = TargetAppKind.detect(appName: appName, bundleIdentifier: app.bundleIdentifier)
        targetLabel = "Target: \(appName) (\(kind.rawValue))"

        // Prime web-style apps as soon as they activate, so they are ready by
        // the time the user clicks the firefly.
        if AccessibilityClient.isTrusted() {
            AccessibilityClient.enableManualAccessibility(for: app)
        }
    }

    private func isUsableTargetApp(_ app: NSRunningApplication) -> Bool {
        let name = app.localizedName?.lowercased() ?? ""
        let bundleID = app.bundleIdentifier?.lowercased() ?? ""

        guard !name.contains("system settings") else { return false }
        guard !name.contains("finder") else { return false }
        guard !name.contains("dock") else { return false }
        guard !name.contains("control center") else { return false }
        guard !name.contains("promptfirefly") else { return false }
        guard !bundleID.contains("promptfirefly") else { return false }

        return true
    }
}
