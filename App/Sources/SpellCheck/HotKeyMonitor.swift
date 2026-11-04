import AppKit
import Carbon
import SpellCheckCore

/// Registers a global hot key via Carbon's `RegisterEventHotKey` and invokes
/// a handler on the main queue when it fires.
final class HotKeyMonitor: @unchecked Sendable {
    private let hotKey: HotKey
    private let handler: @Sendable () -> Void
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    init(hotKey: HotKey, handler: @escaping @Sendable () -> Void) {
        self.hotKey = hotKey
        self.handler = handler
    }

    func start() {
        stop()
        guard hotKey.isUsableAsGlobalHotkey else { return }

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
        guard installStatus == noErr else { return }
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
            return
        }
        hotKeyRef = hotKeyRefOut
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
