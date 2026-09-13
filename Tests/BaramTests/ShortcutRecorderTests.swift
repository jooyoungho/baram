import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Baram

final class ShortcutRecorderTests: XCTestCase {
    private func event(keyCode: Int, flags: NSEvent.ModifierFlags = [], characters: String = "") throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                      timestamp: 0, windowNumber: 0, context: nil,
                                      characters: characters, charactersIgnoringModifiers: characters,
                                      isARepeat: false, keyCode: UInt16(keyCode)))
    }

    func testBareOrShiftOnlyKeyKeepsRecorderWaitingWithAnError() throws {
        let modifiers: [NSEvent.ModifierFlags] = [[], [.shift]]
        for flags in modifiers {
            let action = ShortcutCaptureAction.from(event: try event(keyCode: kVK_ANSI_K, flags: flags, characters: "k"))
            guard case let .invalid(message) = action else {
                return XCTFail("Typing a letter must not become a global shortcut.")
            }
            XCTAssertFalse(message.isEmpty)
        }
    }

    func testEscapeAlwaysCancelsRatherThanBecomingAShortcut() throws {
        let modifiers: [NSEvent.ModifierFlags] = [[], [.command, .option, .shift, .control]]
        for flags in modifiers {
            XCTAssertEqual(ShortcutCaptureAction.from(event: try event(keyCode: kVK_Escape, flags: flags)), .cancel)
        }
    }

    func testCustomChordUsesPhysicalKeyUnderKoreanInput() throws {
        let expected = try XCTUnwrap(KeyboardShortcut(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(cmdKey | optionKey)))
        for characters in ["k", "ㅏ"] {
            let action = ShortcutCaptureAction.from(event: try event(keyCode: kVK_ANSI_K, flags: [.command, .option], characters: characters))
            XCTAssertEqual(action, .shortcut(expected))
        }
    }
}
