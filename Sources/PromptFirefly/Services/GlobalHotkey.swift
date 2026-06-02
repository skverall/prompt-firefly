import AppKit
import Carbon.HIToolbox

/// Registers one system-wide hotkey (⌥⌘R by default) that runs `action` on the main
/// thread. Works without Accessibility permission. Call `register` once at launch.
final class GlobalHotkey {
    static let shared = GlobalHotkey()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (() -> Void)?

    private let identifier: UInt32 = 1
    private let signature: OSType = 0x50464659 // 'PFFY'

    private init() {}

    func register(action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyHandler,
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )

        // keyCode 15 = 'R'; modifiers = Option + Command. Change here to remap.
        let hotKeyID = EventHotKeyID(signature: signature, id: identifier)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_R),
            UInt32(optionKey | cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    fileprivate func fire(id: UInt32) {
        guard id == identifier else { return }
        let action = self.action
        DispatchQueue.main.async {
            action?()
        }
    }
}

/// Top-level C callback (captures nothing, so it converts to a C function pointer).
private func hotKeyHandler(
    callRef: EventHandlerCallRef?,
    eventRef: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData, let eventRef else { return noErr }
    let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()

    var hotKeyID = EventHotKeyID()
    GetEventParameter(
        eventRef,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    hotkey.fire(id: hotKeyID.id)
    return noErr
}
