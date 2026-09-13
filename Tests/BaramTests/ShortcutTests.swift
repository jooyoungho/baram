import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Baram

final class ShortcutTests: XCTestCase {
    private func preferences() -> (UserDefaults, () -> Void) {
        let suite = "local.baram.shortcut-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    func testCustomShortcutRoundTrips() throws {
        let shortcut = try XCTUnwrap(KeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_Slash), carbonModifiers: UInt32(controlKey | optionKey | shiftKey)
        ))
        let decoded = try JSONDecoder().decode(KeyboardShortcut.self, from: JSONEncoder().encode(shortcut))
        XCTAssertEqual(decoded, shortcut)
        XCTAssertEqual(decoded.title, "⌃⌥⇧/")
        XCTAssertEqual(Set([shortcut, decoded]).count, 1)
    }

    func testDefaultAndEveryLegacyPresetMigrate() throws {
        let (defaults, cleanup) = preferences()
        defer { cleanup() }
        XCTAssertEqual(KeyboardShortcut.load(from: defaults), .commandShiftI)
        for preset in ShortcutPreset.allCases {
            defaults.removeObject(forKey: KeyboardShortcut.preferenceKey)
            defaults.set(preset.rawValue, forKey: "shortcut")
            XCTAssertEqual(KeyboardShortcut.load(from: defaults), preset.shortcut)
            XCTAssertNil(defaults.object(forKey: "shortcut"))
            let data = try XCTUnwrap(defaults.data(forKey: KeyboardShortcut.preferenceKey))
            XCTAssertEqual(try JSONDecoder().decode(KeyboardShortcut.self, from: data), preset.shortcut)
        }
    }

    func testNewConfigurationTakesPrecedenceOverLegacy() throws {
        let (defaults, cleanup) = preferences()
        defer { cleanup() }
        let custom = try XCTUnwrap(KeyboardShortcut(keyCode: UInt32(kVK_F7), carbonModifiers: UInt32(optionKey)))
        custom.save(to: defaults)
        defaults.set(ShortcutPreset.commandShiftY.rawValue, forKey: "shortcut")
        XCTAssertEqual(KeyboardShortcut.load(from: defaults), custom)
        XCTAssertNil(defaults.object(forKey: "shortcut"))
    }

    func testMalformedConfigurationFallsBackAndRepairsStorage() throws {
        let (defaults, cleanup) = preferences()
        defer { cleanup() }
        for data in [
            Data("not JSON".utf8),
            Data("{\"keyCode\":34,\"carbonModifiers\":0}".utf8),
            Data("{\"keyCode\":53,\"carbonModifiers\":256}".utf8),
            Data("{\"keyCode\":9999,\"carbonModifiers\":256}".utf8)
        ] {
            defaults.set(data, forKey: KeyboardShortcut.preferenceKey)
            XCTAssertEqual(KeyboardShortcut.load(from: defaults), .commandShiftI)
            let saved = try XCTUnwrap(defaults.data(forKey: KeyboardShortcut.preferenceKey))
            XCTAssertEqual(try JSONDecoder().decode(KeyboardShortcut.self, from: saved), .commandShiftI)
        }
        defaults.set(Data("broken".utf8), forKey: KeyboardShortcut.preferenceKey)
        defaults.set("optionShiftT", forKey: "shortcut")
        XCTAssertEqual(KeyboardShortcut.load(from: defaults), ShortcutPreset.optionShiftT.shortcut)
    }

    func testUnsafeAndUnsupportedChordsCannotBeConstructedOrDecoded() {
        let chords: [(UInt32, UInt32)] = [
            (UInt32(kVK_ANSI_I), 0),
            (UInt32(kVK_ANSI_I), UInt32(shiftKey)),
            (UInt32(kVK_Shift), UInt32(cmdKey)),
            (UInt32(kVK_Command), UInt32(controlKey)),
            (UInt32(kVK_Escape), UInt32(cmdKey)),
            (UInt32(kVK_ANSI_I), UInt32(cmdKey | alphaLock)),
            (UInt32.max, UInt32(cmdKey))
        ]
        for (keyCode, modifiers) in chords {
            XCTAssertNil(KeyboardShortcut(keyCode: keyCode, carbonModifiers: modifiers))
            XCTAssertNotNil(KeyboardShortcut.validationError(keyCode: keyCode, carbonModifiers: modifiers))
            let data = Data("{\"keyCode\":\(keyCode),\"carbonModifiers\":\(modifiers)}".utf8)
            XCTAssertThrowsError(try JSONDecoder().decode(KeyboardShortcut.self, from: data))
        }
    }

    func testCommonKeyFamiliesHavePhysicalAndAccessibleLabels() throws {
        let keys = [kVK_ANSI_A, kVK_ANSI_9, kVK_ANSI_LeftBracket, kVK_Space, kVK_Return,
                    kVK_LeftArrow, kVK_Home, kVK_PageDown, kVK_F1, kVK_F20, kVK_ANSI_Keypad3]
        for key in keys {
            let shortcut = try XCTUnwrap(KeyboardShortcut(keyCode: UInt32(key), carbonModifiers: UInt32(cmdKey)))
            XCTAssertFalse(shortcut.title.isEmpty)
            XCTAssertTrue(shortcut.accessibilityLabel.contains("Command + "))
        }
    }

    @MainActor
    func testRecordingUsesPhysicalKeyUnderKoreanInputAndCapsLock() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command, .shift, .capsLock],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "ㅑ", charactersIgnoringModifiers: "ㅑ", isARepeat: false, keyCode: UInt16(kVK_ANSI_I)
        ))
        XCTAssertEqual(KeyboardShortcut(event: event), .commandShiftI)
        XCTAssertNil(KeyboardShortcut.validationError(for: event))
        let arrow = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.control, .numericPad, .function],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(kVK_LeftArrow)
        ))
        XCTAssertEqual(KeyboardShortcut(event: arrow)?.title, "⌃←")
    }

    @MainActor
    func testModelPersistsCustomChoiceAcrossLaunches() throws {
        let (defaults, cleanup) = preferences()
        defer { cleanup() }
        let historyURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = TranslatorModel(defaults: defaults, historyURL: historyURL)
        XCTAssertEqual(model.shortcut, .commandShiftI)
        let custom = try XCTUnwrap(KeyboardShortcut(keyCode: UInt32(kVK_ANSI_J), carbonModifiers: UInt32(controlKey | optionKey)))
        model.shortcut = custom
        XCTAssertEqual(TranslatorModel(defaults: defaults, historyURL: historyURL).shortcut, custom)
    }

    @MainActor
    func testRegistrationConflictKeepsPreviousChordEvenWhileRecording() throws {
        _ = NSApplication.shared
        // Briefly reserve uncommon chords. If the user already owns either,
        // skip without unregistering or replacing their registration.
        let first = try XCTUnwrap(KeyboardShortcut(
            keyCode: UInt32(kVK_F19), carbonModifiers: UInt32(cmdKey | controlKey | optionKey)
        ))
        let second = try XCTUnwrap(KeyboardShortcut(
            keyCode: UInt32(kVK_F20), carbonModifiers: UInt32(cmdKey | controlKey | optionKey)
        ))
        let owner = GlobalHotKey()
        let replacement = GlobalHotKey()
        defer { owner.unregister(); replacement.unregister() }
        guard owner.register(first), replacement.register(second) else {
            throw XCTSkip("Uncommon test chords are occupied or Carbon registration is unavailable.")
        }
        replacement.isSuspended = true
        XCTAssertFalse(replacement.register(first))
        XCTAssertEqual(replacement.registeredShortcut, second)
        XCTAssertNotNil(replacement.lastError)
        XCTAssertTrue(replacement.register(second))
        XCTAssertNil(replacement.lastError)
        replacement.isSuspended = false
        XCTAssertEqual(replacement.registeredShortcut, second)
    }
}
