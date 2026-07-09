import AppKit
import Carbon.HIToolbox

/// A single system-wide keyboard shortcut, registered through the PUBLIC Carbon
/// `RegisterEventHotKey` API — the classic, stable way menu-bar apps get a global
/// hotkey. It needs NO Accessibility / Input-Monitoring permission (unlike an
/// `NSEvent` global monitor), fires even when DuskMode has no window focused, and
/// has survived every macOS release for ~15 years. Satisfies project rule #2
/// (public, upgrade-proof; no private symbols).
///
/// Keep a strong reference for as long as the shortcut should be live — `deinit`
/// unregisters it.
final class GlobalHotKey {

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let handler: () -> Void
    private let id: UInt32

    /// Dispatch table: the Carbon C callback is global, so it looks the instance up
    /// by hot-key id here rather than capturing `self`.
    private static var registry: [UInt32: GlobalHotKey] = [:]
    private static var nextID: UInt32 = 1
    private static let signature: OSType = 0x44534b4d   // 'DSKM'

    /// - Parameters:
    ///   - keyCode: a `kVK_*` virtual key code (e.g. `kVK_ANSI_C`).
    ///   - modifiers: Carbon modifier mask (`cmdKey`, `optionKey`, `shiftKey`, `controlKey`).
    ///   - handler: run on the main thread each time the shortcut is pressed.
    /// Returns nil if the shortcut couldn't be registered (e.g. already taken).
    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler
        self.id = Self.nextID
        Self.nextID += 1

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hkID = EventHotKeyID()
                let err = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hkID)
                if err == noErr, let target = GlobalHotKey.registry[hkID.id] {
                    target.handler()
                }
                return noErr
            },
            1, &spec, nil, &eventHandlerRef)
        guard installStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let regStatus = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard regStatus == noErr, hotKeyRef != nil else {
            if let h = eventHandlerRef { RemoveEventHandler(h) }
            return nil
        }
        Self.registry[id] = self
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let h = eventHandlerRef { RemoveEventHandler(h) }
        Self.registry[id] = nil
    }
}
