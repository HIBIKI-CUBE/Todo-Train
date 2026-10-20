import AppKit
import Carbon
import SwiftUI

struct ImaYaruShortcut: Equatable, Sendable {
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags
    var characters: String

    var display: String {
        var prefix = ""
        if modifiers.contains(.control) { prefix.append("⌃") }
        if modifiers.contains(.option) { prefix.append("⌥") }
        if modifiers.contains(.shift) { prefix.append("⇧") }
        if modifiers.contains(.command) { prefix.append("⌘") }
        return prefix + characters
    }

    var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        if modifiers.contains(.command) { carbon |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { carbon |= UInt32(shiftKey) }
        if modifiers.contains(.option) { carbon |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }

    /// A shortcut needs a modifier, so a bare letter is not swallowed.
    static func make(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        characters: String
    ) -> ImaYaruShortcut? {
        let mods = modifiers.intersection([.command, .shift, .option, .control])
        guard !mods.isEmpty else { return nil }
        let glyph = glyph(keyCode: keyCode, characters: characters)
        guard glyph != "?" else { return nil }
        return ImaYaruShortcut(keyCode: keyCode, modifiers: mods, characters: glyph)
    }

    private static func glyph(keyCode: UInt16, characters: String) -> String {
        if let named = namedKeys[keyCode] { return named }
        if characters == " " { return "Space" }
        let trimmed = characters.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first.asciiValue.map({ $0 >= 32 }) != false else { return "?" }
        return String(first).uppercased()
    }

    private static let namedKeys: [UInt16: String] = [
        36: "↩",
        48: "⇥",
        49: "Space",
        51: "⌫",
        53: "⎋",
        123: "←",
        124: "→",
        125: "↓",
        126: "↑",
        122: "F1",
        120: "F2",
        99: "F3",
        118: "F4",
        96: "F5",
        97: "F6",
        98: "F7",
        100: "F8",
        101: "F9",
        109: "F10",
        103: "F11",
        111: "F12",
    ]
}

enum ImaYaruShortcutStore {
    static let keyCode = "companion.imaYaruHotKey.keyCode"
    static let modifiers = "companion.imaYaruHotKey.modifiers"
    static let characters = "companion.imaYaruHotKey.characters"

    static func read(_ defaults: UserDefaults) -> ImaYaruShortcut? {
        guard defaults.object(forKey: keyCode) != nil else { return nil }
        let code = UInt16(defaults.integer(forKey: keyCode))
        let flags = NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: modifiers)))
        let characters = defaults.string(forKey: Self.characters) ?? ""
        return ImaYaruShortcut.make(keyCode: code, modifiers: flags, characters: characters)
    }

    static func write(_ shortcut: ImaYaruShortcut?, to defaults: UserDefaults) {
        guard let shortcut else {
            defaults.removeObject(forKey: keyCode)
            defaults.removeObject(forKey: modifiers)
            defaults.removeObject(forKey: characters)
            return
        }
        defaults.set(Int(shortcut.keyCode), forKey: keyCode)
        defaults.set(Int(shortcut.modifiers.rawValue), forKey: modifiers)
        defaults.set(shortcut.characters, forKey: characters)
    }
}

@MainActor
final class ImaYaruHotKeyCenter {
    static let shared = ImaYaruHotKeyCenter()

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var onFire: (@MainActor () -> Void)?
    private var started = false

    func setHandler(_ handler: @escaping @MainActor () -> Void) {
        onFire = handler
        startIfNeeded()
    }

    @discardableResult
    func register(_ shortcut: ImaYaruShortcut?) -> Bool {
        startIfNeeded()
        suspend()
        guard let shortcut else { return true }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifiers,
            EventHotKeyID(signature: 0x494D_5952, id: 1),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        hotKey = ref
        return status == noErr && ref != nil
    }

    func suspend() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }

    private func startIfNeeded() {
        guard !started else { return }
        started = true
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        ImaYaruHotKeyCenter.shared.onFire?()
                    }
                }
                return noErr
            },
            1,
            &spec,
            nil,
            &handler
        )
    }
}

@MainActor
private final class KeyDownCapture {
    private var monitor: Any?

    func start(_ handler: @escaping (NSEvent) -> NSEvent?) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handler)
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

struct ImaYaruShortcutField: View {
    @Binding var shortcut: ImaYaruShortcut?
    @State private var recording = false
    @State private var capture = KeyDownCapture()

    var body: some View {
        HStack(spacing: 8) {
            Button(recording ? "キーを入力" : (shortcut?.display ?? "未設定")) {
                if recording {
                    cancelRecording()
                } else {
                    beginRecording()
                }
            }
            .buttonStyle(.bordered)
            if shortcut != nil, !recording {
                Button("削除") {
                    shortcut = nil
                }
                .buttonStyle(.borderless)
            }
        }
        .onDisappear {
            capture.stop()
            if recording {
                ImaYaruHotKeyCenter.shared.register(shortcut)
            }
        }
    }

    private func beginRecording() {
        ImaYaruHotKeyCenter.shared.suspend()
        recording = true
        capture.start { event in
            if event.keyCode == 53 {
                cancelRecording()
                return nil
            }
            guard let made = ImaYaruShortcut.make(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags,
                characters: event.charactersIgnoringModifiers ?? ""
            ) else {
                return nil
            }
            recording = false
            capture.stop()
            shortcut = made
            return nil
        }
    }

    private func cancelRecording() {
        recording = false
        capture.stop()
        ImaYaruHotKeyCenter.shared.register(shortcut)
    }
}
