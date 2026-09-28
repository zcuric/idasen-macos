import AppKit
import Carbon.HIToolbox
import Foundation
import IdasenKit

/// Registers system-wide hot keys with Carbon, which works without requiring
/// Accessibility or Input Monitoring permissions.
@MainActor
final class GlobalHotKeys {
    private struct Registration {
        let ref: EventHotKeyRef
        var onPress: () -> Void
        var onRelease: (() -> Void)?
    }

    private var registrations: [UInt32: Registration] = [:]
    private var idsByID: [String: UInt32] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    private static let signature: OSType = {
        // 'Idsn'
        let bytes: [UInt8] = [0x49, 0x64, 0x73, 0x6E]
        return OSType(bytes[0]) << 24 | OSType(bytes[1]) << 16 | OSType(bytes[2]) << 8 | OSType(bytes[3])
    }()

    init() {
        installHandler()
    }

    isolated deinit {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    /// Returns false when the shortcut could not be registered (for example
    /// because another app already owns it).
    @discardableResult
    func register(
        _ combo: HotKeyCombo,
        id: String,
        onPress: @escaping () -> Void,
        onRelease: (() -> Void)? = nil
    ) -> Bool {
        guard combo.modifierFlags.rawValue != 0 else { return false }
        guard idsByID[id] == nil else { return false }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: nextID)
        var ref: EventHotKeyRef?
        // The event dispatcher target delivers hot keys while other apps are
        // frontmost; the application target only works in-process.
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode),
            Self.carbonModifiers(from: combo.modifierFlags),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }

        registrations[nextID] = Registration(ref: ref, onPress: onPress, onRelease: onRelease)
        idsByID[id] = nextID
        nextID += 1
        return true
    }

    func unregisterAll() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()
        idsByID.removeAll()
    }

    fileprivate func handle(id: UInt32, isRelease: Bool) {
        guard let registration = registrations[id] else { return }
        if isRelease {
            registration.onRelease?()
        } else {
            registration.onPress()
        }
    }

    private func installHandler() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                let manager = Unmanaged<GlobalHotKeys>.fromOpaque(userData).takeUnretainedValue()
                let id = hotKeyID.id
                let isRelease = GetEventKind(event) == UInt32(kEventHotKeyReleased)
                MainActor.assumeIsolated { manager.handle(id: id, isRelease: isRelease) }
                return noErr
            },
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }
}
