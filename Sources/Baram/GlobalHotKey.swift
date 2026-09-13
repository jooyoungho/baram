import AppKit
import Carbon.HIToolbox

/// A physical key and its modifiers, independent of the current input language.
/// Only valid, recordable chords can be created or decoded from preferences.
struct KeyboardShortcut: Codable, Hashable {
    let keyCode: UInt32
    let carbonModifiers: UInt32

    static let preferenceKey = "shortcutConfiguration"
    static let commandShiftI = KeyboardShortcut(
        keyCode: UInt32(kVK_ANSI_I), carbonModifiers: UInt32(cmdKey | shiftKey)
    )!

    private static let allowedModifiers = UInt32(cmdKey | controlKey | optionKey | shiftKey)
    private static let requiredModifiers = UInt32(cmdKey | controlKey | optionKey)

    init?(keyCode: UInt32, carbonModifiers: UInt32) {
        guard Self.validationError(keyCode: keyCode, carbonModifiers: carbonModifiers) == nil else { return nil }
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: Self.carbonModifiers(for: event.modifierFlags))
    }

    static func validationError(for event: NSEvent) -> String? {
        guard event.type == .keyDown else { return "조합에 사용할 키를 눌러 주세요." }
        return validationError(keyCode: UInt32(event.keyCode), carbonModifiers: carbonModifiers(for: event.modifierFlags))
    }

    static func validationError(keyCode: UInt32, carbonModifiers: UInt32) -> String? {
        guard keyCode != UInt32(kVK_Escape) else { return "Esc는 단축키 입력 취소에 사용해요." }
        guard keyNames[keyCode] != nil else { return "문자, 숫자, 기호, 방향키 또는 F1–F20 키를 함께 눌러 주세요." }
        guard carbonModifiers & ~allowedModifiers == 0 else { return "⌘, ⌃, ⌥, ⇧ 조합으로 설정해 주세요." }
        guard carbonModifiers & requiredModifiers != 0 else { return "⌘, ⌃, ⌥ 중 하나를 함께 눌러 주세요. ⇧만으로는 설정할 수 없어요." }
        return nil
    }

    private static func carbonModifiers(for flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        // Caps Lock, numeric-pad and function flags describe keyboard state or
        // the key itself; Carbon registers only the four chord modifiers above.
        return result
    }

    var title: String {
        var result = ""
        // Preserve the familiar default ⌘⇧I while keeping every chord consistent.
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        return result + Self.keyNames[keyCode]!
    }

    var displayName: String { title }

    var accessibilityLabel: String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("Control") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("Option") }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("Command") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("Shift") }
        parts.append(Self.accessibleKeyNames[keyCode] ?? Self.keyNames[keyCode]!)
        return parts.joined(separator: " + ") + " — 클립보드 번역"
    }

    private enum CodingKeys: String, CodingKey { case keyCode, carbonModifiers }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let keyCode = try values.decode(UInt32.self, forKey: .keyCode)
        let modifiers = try values.decode(UInt32.self, forKey: .carbonModifiers)
        guard let valid = Self(keyCode: keyCode, carbonModifiers: modifiers) else {
            throw DecodingError.dataCorruptedError(
                forKey: .keyCode, in: values,
                debugDescription: Self.validationError(keyCode: keyCode, carbonModifiers: modifiers) ?? "Invalid shortcut"
            )
        }
        self = valid
    }

    static func load(from defaults: UserDefaults) -> Self {
        let shortcut: Self
        if let data = defaults.data(forKey: preferenceKey),
           let stored = try? JSONDecoder().decode(Self.self, from: data) {
            shortcut = stored
        } else if let legacy = defaults.string(forKey: "shortcut"),
                  let preset = ShortcutPreset(rawValue: legacy) {
            shortcut = preset.shortcut
        } else {
            shortcut = .commandShiftI
        }
        shortcut.save(to: defaults)
        return shortcut
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.preferenceKey)
        defaults.removeObject(forKey: "shortcut")
    }

    private static let keyNames: [UInt32: String] = {
        let pairs: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"),
            (kVK_ANSI_E, "E"), (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"),
            (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"), (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"),
            (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"), (kVK_ANSI_P, "P"),
            (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
            (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"),
            (kVK_ANSI_Y, "Y"), (kVK_ANSI_Z, "Z"),
            (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"),
            (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"),
            (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"),
            (kVK_ANSI_Equal, "="), (kVK_ANSI_Minus, "-"), (kVK_ANSI_LeftBracket, "["),
            (kVK_ANSI_RightBracket, "]"), (kVK_ANSI_Quote, "'"), (kVK_ANSI_Semicolon, ";"),
            (kVK_ANSI_Backslash, "\\"), (kVK_ANSI_Comma, ","), (kVK_ANSI_Slash, "/"),
            (kVK_ANSI_Period, "."), (kVK_ANSI_Grave, "`"),
            (kVK_Space, "Space"), (kVK_Return, "↩"), (kVK_Tab, "⇥"), (kVK_Delete, "⌫"),
            (kVK_ForwardDelete, "⌦"), (kVK_Home, "↖"), (kVK_End, "↘"),
            (kVK_PageUp, "⇞"), (kVK_PageDown, "⇟"), (kVK_Help, "Help"),
            (kVK_LeftArrow, "←"), (kVK_RightArrow, "→"), (kVK_UpArrow, "↑"), (kVK_DownArrow, "↓"),
            (kVK_F1, "F1"), (kVK_F2, "F2"), (kVK_F3, "F3"), (kVK_F4, "F4"),
            (kVK_F5, "F5"), (kVK_F6, "F6"), (kVK_F7, "F7"), (kVK_F8, "F8"),
            (kVK_F9, "F9"), (kVK_F10, "F10"), (kVK_F11, "F11"), (kVK_F12, "F12"),
            (kVK_F13, "F13"), (kVK_F14, "F14"), (kVK_F15, "F15"), (kVK_F16, "F16"),
            (kVK_F17, "F17"), (kVK_F18, "F18"), (kVK_F19, "F19"), (kVK_F20, "F20"),
            (kVK_ANSI_Keypad0, "Num 0"), (kVK_ANSI_Keypad1, "Num 1"), (kVK_ANSI_Keypad2, "Num 2"),
            (kVK_ANSI_Keypad3, "Num 3"), (kVK_ANSI_Keypad4, "Num 4"), (kVK_ANSI_Keypad5, "Num 5"),
            (kVK_ANSI_Keypad6, "Num 6"), (kVK_ANSI_Keypad7, "Num 7"), (kVK_ANSI_Keypad8, "Num 8"),
            (kVK_ANSI_Keypad9, "Num 9"), (kVK_ANSI_KeypadDecimal, "Num ."),
            (kVK_ANSI_KeypadMultiply, "Num *"), (kVK_ANSI_KeypadPlus, "Num +"),
            (kVK_ANSI_KeypadClear, "Num Clear"), (kVK_ANSI_KeypadDivide, "Num /"),
            (kVK_ANSI_KeypadEnter, "Num ↩"), (kVK_ANSI_KeypadMinus, "Num -"),
            (kVK_ANSI_KeypadEquals, "Num =")
        ]
        return Dictionary(uniqueKeysWithValues: pairs.map { (UInt32($0.0), $0.1) })
    }()

    private static let accessibleKeyNames: [UInt32: String] = [
        UInt32(kVK_Return): "Return", UInt32(kVK_Tab): "Tab", UInt32(kVK_Delete): "Delete",
        UInt32(kVK_ForwardDelete): "Forward Delete", UInt32(kVK_Home): "Home", UInt32(kVK_End): "End",
        UInt32(kVK_PageUp): "Page Up", UInt32(kVK_PageDown): "Page Down",
        UInt32(kVK_LeftArrow): "Left Arrow", UInt32(kVK_RightArrow): "Right Arrow",
        UInt32(kVK_UpArrow): "Up Arrow", UInt32(kVK_DownArrow): "Down Arrow"
    ]
}

enum ShortcutPreset: String, CaseIterable, Identifiable {
    case commandShiftI
    case optionShiftT
    case controlOptionT
    case commandShiftY

    var id: String { rawValue }
    var title: String { shortcut.title }
    var displayName: String { shortcut.displayName }
    var accessibilityLabel: String { shortcut.accessibilityLabel }

    var shortcut: KeyboardShortcut { KeyboardShortcut(keyCode: keyCode, carbonModifiers: carbonModifiers)! }

    var keyCode: UInt32 {
        switch self {
        case .commandShiftI: UInt32(kVK_ANSI_I)
        case .commandShiftY: UInt32(kVK_ANSI_Y)
        case .optionShiftT, .controlOptionT: UInt32(kVK_ANSI_T)
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .commandShiftI, .commandShiftY: UInt32(cmdKey | shiftKey)
        case .optionShiftT: UInt32(optionKey | shiftKey)
        case .controlOptionT: UInt32(controlKey | optionKey)
        }
    }
}

/// Carbon hot keys deliver a registered chord without monitoring other keys or
/// requiring Accessibility / Input Monitoring permissions.
@MainActor
final class GlobalHotKey {
    var onPressed: (() -> Void)?
    var onRecordedShortcut: ((KeyboardShortcut) -> Void)?
    var isSuspended = false
    private(set) var lastError: String?
    private(set) var registeredShortcut: KeyboardShortcut?

    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var hotKeyID: UInt32 = 0
    private static var nextID: UInt32 = 1
    private static let signature: OSType = 0x4241524D // BARM

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    @discardableResult
    func register(_ shortcut: KeyboardShortcut) -> Bool {
        if registeredShortcut == shortcut, hotKey != nil {
            lastError = nil
            return true
        }
        guard installHandlerIfNeeded() else { return false }

        let candidateID = Self.nextID
        Self.nextID &+= 1
        var candidate: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: candidateID),
            GetApplicationEventTarget(),
            0,
            &candidate
        )
        guard status == noErr, let candidate else {
            if status == eventHotKeyExistsErr {
                lastError = "\(shortcut.title) 단축키를 다른 앱이 사용 중입니다. 다른 단축키를 선택해 주세요."
            } else {
                lastError = "전역 단축키를 등록하지 못했습니다. (오류 \(status))"
            }
            return false
        }

        // Keep the previous shortcut working when a replacement is occupied.
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = candidate
        hotKeyID = candidateID
        registeredShortcut = shortcut
        lastError = nil
        return true
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        hotKeyID = 0
        registeredShortcut = nil
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }

    private func installHandlerIfNeeded() -> Bool {
        guard eventHandler == nil else { return true }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var receivedID = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &receivedID
                )
                guard result == noErr else { return result }
                // Application event handlers run on AppKit's main event loop.
                // Never retain self in Carbon's context; remove the handler at
                // teardown before the unretained context can become invalid.
                return MainActor.assumeIsolated {
                    let owner = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                    guard receivedID.signature == GlobalHotKey.signature,
                          receivedID.id == owner.hotKeyID else {
                        return OSStatus(eventNotHandledErr)
                    }
                    if owner.isSuspended {
                        // Carbon owns the currently registered chord, so a local
                        // NSEvent recorder may not receive it. Forward that chord
                        // explicitly without releasing its registration.
                        if let shortcut = owner.registeredShortcut { owner.onRecordedShortcut?(shortcut) }
                    } else {
                        owner.onPressed?()
                    }
                    return noErr
                }
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard status == noErr else {
            lastError = "단축키 이벤트를 준비하지 못했습니다. (오류 \(status))"
            return false
        }
        return true
    }
}
