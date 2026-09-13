import AppKit
import Carbon
import XCTest
@testable import Baram

final class ClipboardTests: XCTestCase {
    @MainActor
    func testEditorConstructedWithoutContainerAcceptsTypingAndSelection() {
        let view = PlainTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 150), textContainer: nil)
        XCTAssertNotNil(view.textContainer)
        XCTAssertNotNil(view.layoutManager)
        XCTAssertNotNil(view.textStorage)
        XCTAssertFalse(view.isRichText)
        let text = "Hello\n안녕하세요\nこんにちは"
        view.insertText(text, replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(view.string, text)
        view.selectAll(nil)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: (text as NSString).length))
        XCTAssertEqual(view.writablePasteboardTypes, [.string])
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes))
        XCTAssertEqual(PlainClipboard.read(from: pasteboard), text)
        XCTAssertNil(pasteboard.data(forType: .rtf))
        XCTAssertNil(pasteboard.data(forType: .html))
    }

    @MainActor
    func testPlainTextTakesPrecedenceOverRichRepresentations() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Hello\n안녕하세요\nこんにちは", forType: .string)
        pasteboard.setString("<b>This should not win</b>", forType: .html)
        XCTAssertEqual(PlainClipboard.read(from: pasteboard), "Hello\n안녕하세요\nこんにちは")
    }

    @MainActor
    func testWritingTextClearsFormattingAndPreservesNewlines() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("<b>Rich</b>", forType: .html)
        pasteboard.setData(Data("{\\rtf1 Rich}".utf8), forType: .rtf)
        XCTAssertTrue(PlainClipboard.write("Bold became plain\n\nNext paragraph", to: pasteboard))
        let types = Set(pasteboard.types ?? [])
        XCTAssertTrue(types.contains(.string))
        // AppKit may synthesize its historical NSStringPboardType alias; both
        // are plain text. No rich format should survive clearing the clipboard.
        XCTAssertTrue(types.isSubset(of: [.string, .init("NSStringPboardType")]))
        XCTAssertEqual(PlainClipboard.read(from: pasteboard), "Bold became plain\n\nNext paragraph")
    }

    @MainActor
    func testRichTextOnlyClipboardIsExtractedAsUnicodeText() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let attributed = NSAttributedString(
            string: "제목\nSecond line 日本語",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 18)]
        )
        let rtf = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        pasteboard.setData(rtf, forType: .rtf)
        XCTAssertEqual(PlainClipboard.read(from: pasteboard), attributed.string)
    }

    @MainActor
    func testNonTextClipboardHasNoTranslationInput() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setData(Data([0, 1, 2]), forType: .png)
        XCTAssertNil(PlainClipboard.read(from: pasteboard))
    }

    func testShortcutPresetsUseDistinctChords() {
        XCTAssertEqual(ShortcutPreset.optionShiftT.title, "⌥⇧T")
        XCTAssertEqual(ShortcutPreset.commandShiftI.title, "⌘⇧I")
        XCTAssertEqual(ShortcutPreset.commandShiftI.keyCode, UInt32(kVK_ANSI_I))
        XCTAssertEqual(ShortcutPreset.commandShiftI.carbonModifiers, UInt32(cmdKey | shiftKey))
        XCTAssertEqual(Set(ShortcutPreset.allCases.map(\.id)).count, 4)
        let chords = ShortcutPreset.allCases.map { "\($0.keyCode):\($0.carbonModifiers)" }
        XCTAssertEqual(Set(chords).count, 4)
    }

    @MainActor
    func testResultCopyShortcutWorksWithKoreanCharactersAndCapsLock() throws {
        _ = NSApplication.shared
        let panel = TranslatorPanel(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        var copies = 0
        panel.onCopyResult = { copies += 1 }
        for (characters, flags) in [
            ("C", NSEvent.ModifierFlags([.command, .shift])),
            ("ㅊ", NSEvent.ModifierFlags([.command, .shift, .capsLock])),
            ("c", NSEvent.ModifierFlags([.command, .shift, .function]))
        ] {
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: UInt16(kVK_ANSI_C)
            ))
            XCTAssertTrue(panel.performKeyEquivalent(with: event))
        }
        XCTAssertEqual(copies, 3)
    }
}
