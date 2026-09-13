import AppKit
import Translation
import XCTest
@testable import Baram

final class TranslatorModelTests: XCTestCase {
    @MainActor
    private func fixture() -> (TranslatorModel, UserDefaults, URL, () -> Void) {
        let suite = "BaramTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let historyURL = directory.appendingPathComponent("history.json")
        let model = TranslatorModel(defaults: defaults, historyURL: historyURL)
        return (model, defaults, historyURL, {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        })
    }

    func testSmartTargetMappingAndExplicitTargetPreference() {
        for language in ["en", "ja", "zh-Hans", "fr"] {
            XCTAssertEqual(AppLanguage.target(for: language, preferred: "ja", smart: true), "ko")
        }
        XCTAssertEqual(AppLanguage.target(for: "ko", preferred: "ko", smart: true), "en")
        XCTAssertEqual(AppLanguage.target(for: nil, preferred: "ja", smart: true), "ko")
        XCTAssertEqual(AppLanguage.target(for: "ko", preferred: "ja", smart: false), "ja")
    }

    @MainActor
    func testAutomaticPairSwitchesWithActualEnglishAndKoreanInput() {
        let (model, _, _, cleanUp) = fixture()
        defer { cleanUp() }
        model.input = "안녕하세요. 오늘 회의는 오후 세 시에 시작합니다. 필요한 자료를 미리 준비해 주세요."
        model.translate()
        XCTAssertEqual(model.detectedID, "ko")
        XCTAssertEqual(model.targetID, "en")
        XCTAssertEqual(model.configuration?.target?.languageCode?.identifier, "en")

        model.input = "Hello. Today's meeting begins at three in the afternoon. Please prepare the documents before we start."
        model.translate()
        XCTAssertEqual(model.detectedID, "en")
        XCTAssertEqual(model.targetID, "ko")
        XCTAssertEqual(model.configuration?.target?.languageCode?.identifier, "ko")
    }

    @MainActor
    func testEditingClearsStaleOutputAndPreparedSession() {
        let (model, _, _, cleanUp) = fixture()
        defer { cleanUp() }
        model.sourceID = "en"
        model.targetID = "ko"
        model.input = "Original request"
        model.translate()
        XCTAssertTrue(model.busy)
        XCTAssertNotNil(model.configuration)
        model.output = "이전 결과"
        model.error = "이전 오류"

        model.autoTranslate = false
        model.input = "Replacement request"
        model.inputEdited()
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.configuration)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.output, "")
        XCTAssertEqual(model.input, "Replacement request")
    }

    @MainActor
    func testRepeatedTranslationInvalidatesSameLanguageConfiguration() throws {
        let (model, _, _, cleanUp) = fixture()
        defer { cleanUp() }
        model.sourceID = "en"
        model.targetID = "ko"
        model.input = "First request"
        model.translate()
        let first = try XCTUnwrap(model.configuration)

        model.input = "A different request using the same language pair"
        model.translate()
        let second = try XCTUnwrap(model.configuration)
        XCTAssertEqual(first.source, second.source)
        XCTAssertEqual(first.target, second.target)
        XCTAssertGreaterThan(second.version, first.version)
        XCTAssertNotEqual(first, second)
    }

    @MainActor
    func testSameLanguagePreservesTextForFormattingRemoval() {
        let (model, _, historyURL, cleanUp) = fixture()
        defer { cleanUp() }
        model.sourceID = "ko"
        model.targetID = "ko"
        model.input = "  제목\n\n본문\t항목\n마지막 줄  \n"
        model.translate()
        XCTAssertEqual(model.output, model.input)
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.configuration)
        XCTAssertNil(model.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyURL.path))
    }

    @MainActor
    func testSelectingTargetDisablesAutomaticPair() {
        let (model, _, _, cleanUp) = fixture()
        defer { cleanUp() }
        XCTAssertTrue(model.smartPair)
        model.selectTarget("ja")
        model.input = "This text should use the target language I selected."
        model.translate()
        XCTAssertFalse(model.smartPair)
        XCTAssertEqual(model.targetID, "ja")
        XCTAssertEqual(model.configuration?.target?.languageCode?.identifier, "ja")
    }

    @MainActor
    func testHistoryRequiresOptInAndPreferenceSurvivesReload() {
        let (model, defaults, historyURL, cleanUp) = fixture()
        defer { cleanUp() }
        XCTAssertFalse(model.saveHistory)
        XCTAssertTrue(model.history.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyURL.path))

        model.saveHistory = true
        XCTAssertTrue(TranslatorModel(defaults: defaults, historyURL: historyURL).saveHistory)
        model.saveHistory = false
        XCTAssertFalse(TranslatorModel(defaults: defaults, historyURL: historyURL).saveHistory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyURL.path))
    }

    @MainActor
    func testRestoringHistoryCancelsPendingTranslation() {
        let (model, _, _, cleanUp) = fixture()
        defer { cleanUp() }
        model.sourceID = "en"
        model.targetID = "ko"
        model.input = "Pending text"
        model.translate()
        let record = TranslationRecord(source: "保存した文章", target: "저장한 문장", sourceCode: "ja", targetCode: "ko")
        model.restore(record)
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.configuration)
        XCTAssertEqual(model.input, record.source)
        XCTAssertEqual(model.output, record.target)
        XCTAssertEqual(model.sourceID, "ja")
        XCTAssertEqual(model.targetID, "ko")
    }

    @MainActor
    func testOversizeInputRemainsAvailableWithoutPreparingTranslation() {
        let (model, _, _, cleanUp) = fixture()
        defer { cleanUp() }
        model.input = String(repeating: "가", count: 30_001)
        model.translate()
        XCTAssertEqual(model.input.count, 30_001)
        XCTAssertNotNil(model.error)
        XCTAssertNil(model.configuration)
        XCTAssertFalse(model.busy)
    }

    @MainActor
    func testClearingInputCancelsScheduledTranslation() async throws {
        let (model, _, _, cleanUp) = fixture()
        defer { cleanUp() }
        model.sourceID = "en"
        model.input = "Scheduled input"
        model.inputEdited()
        model.clear()
        try await Task.sleep(for: .milliseconds(850))
        XCTAssertEqual(model.input, "")
        XCTAssertNil(model.configuration)
        XCTAssertFalse(model.busy)
    }

    @MainActor
    func testTurningOffAutomaticTranslationCancelsScheduledTranslation() async throws {
        let (model, _, _, cleanUp) = fixture()
        defer { cleanUp() }
        model.sourceID = "en"
        model.input = "Scheduled input"
        model.inputEdited()
        model.autoTranslate = false
        try await Task.sleep(for: .milliseconds(850))
        XCTAssertNil(model.configuration)
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.input, "Scheduled input")
    }

    @MainActor
    func testShortcutSelectsClipboardSourceBeforeTranslationAndKeepsSelectionOnCompletion() throws {
        let (model, _, _, cleanUp) = fixture()
        defer { cleanUp() }
        let pasteboard = NSPasteboard(name: .init("BaramTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Hello from the clipboard", forType: .string)
        model.sourceID = "en"
        model.targetID = "ko"

        model.pasteAndTranslate(selectSource: true, from: pasteboard)
        let requestID = try XCTUnwrap(model.activeRequestID)
        let selectionID = try XCTUnwrap(model.sourceSelectionRequest)
        XCTAssertEqual(model.input, "Hello from the clipboard")
        XCTAssertTrue(model.busy)
        XCTAssertEqual(model.output, "")

        model.completeTranslation(response(source: model.input, target: "클립보드에서 인사합니다"), requestID: requestID)
        XCTAssertEqual(model.output, "클립보드에서 인사합니다")
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.sourceSelectionRequest, selectionID)
    }

    @MainActor
    func testManualTranslationAndPasteDoNotRequestAutomaticFocus() throws {
        let (model, _, _, cleanUp) = fixture()
        defer { cleanUp() }
        model.sourceID = "en"
        model.targetID = "ko"
        model.input = "Text entered by hand"
        model.translate()
        let requestID = try XCTUnwrap(model.activeRequestID)

        model.completeTranslation(response(source: model.input, target: "직접 입력한 문장"), requestID: requestID)
        XCTAssertEqual(model.output, "직접 입력한 문장")
        XCTAssertNil(model.sourceSelectionRequest)

        let pasteboard = NSPasteboard(name: .init("BaramTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Manually pasted text", forType: .string)
        model.pasteAndTranslate(from: pasteboard)
        XCTAssertEqual(model.input, "Manually pasted text")
        XCTAssertNil(model.sourceSelectionRequest)
    }

    @MainActor
    func testReplacedOrEditedShortcutRequestCannotPublishStaleResultOrSelection() throws {
        let (model, _, _, cleanUp) = fixture()
        defer { cleanUp() }
        model.sourceID = "en"
        model.targetID = "ko"
        model.autoTranslate = false
        let pasteboard = NSPasteboard(name: .init("BaramTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Old clipboard text", forType: .string)
        model.pasteAndTranslate(selectSource: true, from: pasteboard)
        let oldRequestID = try XCTUnwrap(model.activeRequestID)
        let oldSelectionID = try XCTUnwrap(model.sourceSelectionRequest)
        pasteboard.clearContents()
        pasteboard.setString("New clipboard text", forType: .string)
        model.pasteAndTranslate(selectSource: true, from: pasteboard)
        let newRequestID = try XCTUnwrap(model.activeRequestID)
        let newSelectionID = try XCTUnwrap(model.sourceSelectionRequest)
        XCTAssertNotEqual(oldSelectionID, newSelectionID)

        model.completeTranslation(response(source: "Old clipboard text", target: "이전 결과"), requestID: oldRequestID)
        XCTAssertEqual(model.output, "")
        XCTAssertEqual(model.sourceSelectionRequest, newSelectionID)
        XCTAssertTrue(model.busy)
        XCTAssertEqual(model.activeRequestID, newRequestID)

        model.input = "I am editing the new text"
        model.inputEdited()
        model.completeTranslation(response(source: "New clipboard text", target: "새 결과"), requestID: newRequestID)
        XCTAssertEqual(model.output, "")
        XCTAssertNil(model.sourceSelectionRequest)
        XCTAssertFalse(model.busy)
    }

    @MainActor
    func testDismissalAndPageNavigationSuppressPendingAutomaticSelection() throws {
        for destination in [TranslatorModel.Page.translate, .settings, .history] {
            let (model, _, _, cleanUp) = fixture()
            defer { cleanUp() }
            model.sourceID = "en"
            model.targetID = "ko"
            let pasteboard = NSPasteboard(name: .init("BaramTests.\(UUID().uuidString)"))
            defer { pasteboard.releaseGlobally() }
            pasteboard.setString("A pending translation", forType: .string)
            model.pasteAndTranslate(selectSource: true, from: pasteboard)
            let requestID = try XCTUnwrap(model.activeRequestID)
            XCTAssertNotNil(model.sourceSelectionRequest)

            if destination == .translate { model.cancelAutomaticSelection() }
            else { model.page = destination }
            XCTAssertNil(model.sourceSelectionRequest)
            model.completeTranslation(response(source: model.input, target: "완료된 번역"), requestID: requestID)
            XCTAssertEqual(model.output, "완료된 번역")
            XCTAssertNil(model.sourceSelectionRequest)
        }
    }

    @MainActor
    func testSameLanguageShortcutSelectsOriginalAndEmptyClipboardClearsSelection() {
        let (model, _, _, cleanUp) = fixture()
        defer { cleanUp() }
        model.sourceID = "ko"
        model.targetID = "ko"
        let pasteboard = NSPasteboard(name: .init("BaramTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let original = "  제목\n\n본문\t항목  "
        pasteboard.setString(original, forType: .string)
        model.pasteAndTranslate(selectSource: true, from: pasteboard)
        XCTAssertEqual(model.input, original)
        XCTAssertEqual(model.output, model.input)
        XCTAssertFalse(model.busy)
        XCTAssertNotNil(model.sourceSelectionRequest)

        pasteboard.clearContents()
        model.pasteAndTranslate(selectSource: true, from: pasteboard)
        XCTAssertNotNil(model.error)
        XCTAssertNil(model.sourceSelectionRequest)
        XCTAssertEqual(model.output, "")
        XCTAssertFalse(model.busy)
    }

    @MainActor
    func testSourceRemainsSelectableWhenTranslationReturnsNothingOrInputExceedsLimit() throws {
        let (model, _, _, cleanUp) = fixture()
        defer { cleanUp() }
        model.sourceID = "en"
        model.targetID = "ko"
        let pasteboard = NSPasteboard(name: .init("BaramTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Text without a returned translation", forType: .string)
        model.pasteAndTranslate(selectSource: true, from: pasteboard)
        let requestID = try XCTUnwrap(model.activeRequestID)
        let selectionID = try XCTUnwrap(model.sourceSelectionRequest)
        model.completeTranslation(response(source: model.input, target: ""), requestID: requestID)
        XCTAssertEqual(model.sourceSelectionRequest, selectionID)

        let longOriginal = String(repeating: "x", count: 30_001)
        pasteboard.clearContents()
        pasteboard.setString(longOriginal, forType: .string)
        model.pasteAndTranslate(selectSource: true, from: pasteboard)
        XCTAssertEqual(model.input, longOriginal)
        XCTAssertNotNil(model.error)
        XCTAssertNotNil(model.sourceSelectionRequest)
        XCTAssertNotEqual(model.sourceSelectionRequest, selectionID)
        XCTAssertNil(model.activeRequestID)
        XCTAssertFalse(model.busy)
    }

    private func response(source: String, target: String) -> TranslationSession.Response {
        TranslationSession.Response(
            sourceLanguage: Locale.Language(identifier: "en"),
            targetLanguage: Locale.Language(identifier: "ko"),
            sourceText: source,
            targetText: target
        )
    }
}
