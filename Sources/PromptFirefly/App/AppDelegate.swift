import AppKit
import SwiftUI

extension Notification.Name {
    static let promptFireflyShowSettings = Notification.Name("promptFireflyShowSettings")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var fireflyWindowController: FireflyWindowController?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        AppState.shared.loadDefaultProjectFolderIfNeeded()
        AppState.shared.refreshAccessibilityStatus()
        TargetAppTracker.shared.start()

        GlobalHotkey.shared.register {
            Task { @MainActor in
                AppState.shared.rewriteFocusedPrompt()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showSettingsWindow),
            name: .promptFireflyShowSettings,
            object: nil
        )

        let fireflyWindowController = FireflyWindowController(appState: AppState.shared)
        self.fireflyWindowController = fireflyWindowController
        fireflyWindowController.show()

        if SettingsStore.shared.apiKey.isEmpty {
            showSettingsWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(appState: AppState.shared)
        }

        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class FireflyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FireflyWindowController: NSWindowController {
    init(appState: AppState) {
        let size = NSSize(width: 74, height: 74)
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let origin = NSPoint(
            x: screenFrame.maxX - size.width - 28,
            y: screenFrame.midY - size.height / 2
        )

        let panel = FireflyPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let contentView = ClearHostingView(rootView: FireflyView(appState: appState))
        contentView.clickAction = {
            appState.rewriteFocusedPrompt()
        }

        panel.contentView = contentView
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        super.init(window: panel)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        window?.orderFrontRegardless()
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    init(appState: AppState) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Prompt Firefly Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(appState: appState))

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

private final class ClearHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    var clickAction: (() -> Void)?

    private var dragStartScreenLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var dragDistance: CGFloat = 0

    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.backgroundColor = .clear
        window?.isOpaque = false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        dragStartScreenLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin
        dragDistance = 0
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            let window,
            let dragStartScreenLocation,
            let dragStartWindowOrigin
        else {
            return
        }

        let currentLocation = NSEvent.mouseLocation
        let deltaX = currentLocation.x - dragStartScreenLocation.x
        let deltaY = currentLocation.y - dragStartScreenLocation.y
        dragDistance = hypot(deltaX, deltaY)

        guard dragDistance > 2 else { return }

        window.setFrameOrigin(
            NSPoint(
                x: dragStartWindowOrigin.x + deltaX,
                y: dragStartWindowOrigin.y + deltaY
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStartScreenLocation = nil
            dragStartWindowOrigin = nil
            dragDistance = 0
        }

        if dragDistance < 8 {
            clickAction?()
        }
    }
}
