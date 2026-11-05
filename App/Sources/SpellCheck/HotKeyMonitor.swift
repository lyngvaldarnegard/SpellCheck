import AppKit
import Carbon
import SpellCheckCore

/// Registers a global hot key via Carbon's `RegisterEventHotKey` and invokes
/// a handler on the main queue when it fires.
///
/// Carbon hot keys need no Input Monitoring permission — they only require
/// regular app launch. (Input Monitoring is needed by *event tap* approaches
/// that observe all keystrokes; `RegisterEventHotKey` never does that.)
final class HotKeyMonitor: @unchecked Sendable {
    private let hotKey: HotKey
    private let handler: @Sendable () -> Void
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    init(hotKey: HotKey, handler: @escaping @Sendable () -> Void) {
        self.hotKey = hotKey
        self.handler = handler
    }

    /// Registers the hot key. Returns nil on success, or a human-readable
    /// reason when registration failed (e.g. the shortcut is already taken).
    @discardableResult
    func start() -> String? {
        stop()
        guard hotKey.isUsableAsGlobalHotkey else {
            return "No shortcut is configured — pick one in SpellCheck Settings."
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        var handlerRef: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                monitor.handler()
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &handlerRef
        )
        guard installStatus == noErr else {
            return "Could not install the hot key handler (error \(installStatus))."
        }
        eventHandlerRef = handlerRef

        var hotKeyID = EventHotKeyID(signature: OSType(0x5350434B) /* "SPCK" */, id: 1)
        var hotKeyRefOut: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            hotKey.keyCode,
            carbonModifiers(hotKey.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRefOut
        )
        guard registerStatus == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            eventHandlerRef = nil
            if registerStatus == OSStatus(eventHotKeyExistsErr) {
                return "The shortcut \(hotKey.description) is already used by another application — pick a different one in SpellCheck Settings."
            }
            return "Could not register \(hotKey.description) (error \(registerStatus))."
        }
        hotKeyRef = hotKeyRefOut
        return nil
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    deinit {
        stop()
    }

    /// Converts the CGEventFlags-style bits stored in `HotKey` into the Carbon
    /// modifier mask that `RegisterEventHotKey` expects.
    private func carbonModifiers(_ flags: UInt32) -> UInt32 {
        var result: UInt32 = 0
        if flags & ModifierFlags.command != 0 { result |= UInt32(cmdKey) }
        if flags & ModifierFlags.shift != 0 { result |= UInt32(shiftKey) }
        if flags & ModifierFlags.option != 0 { result |= UInt32(optionKey) }
        if flags & ModifierFlags.control != 0 { result |= UInt32(controlKey) }
        return result
    }
}
