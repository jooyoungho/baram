import AppKit
import Combine
import Translation
import AVFoundation

@MainActor
final class TranslatorModel: ObservableObject {
    enum Page { case translate, history, settings }
    struct Request {
        let id: UUID
        let text: String
        let source: String?
        let target: String
    }
    struct CopyFeedback: Equatable {
        let id = UUID()
        let source: Bool
    }

    @Published var input = ""
    @Published var output = ""
    @Published var sourceID: String { didSet { defaults.set(sourceID, forKey: "source") } }
    @Published var targetID: String { didSet { defaults.set(targetID, forKey: "target") } }
    @Published var smartPair: Bool { didSet { defaults.set(smartPair, forKey: "smartPair") } }
    @Published var autoTranslate: Bool { didSet { defaults.set(autoTranslate, forKey: "autoTranslate") } }
    @Published var saveHistory: Bool { didSet { defaults.set(saveHistory, forKey: "saveHistory") } }
    @Published var pinned = false
    @Published var page: Page = .translate {
        didSet { if page != .translate { cancelAutomaticSelection() } }
    }
    @Published var busy = false
    @Published var error: String?
    @Published var status = "기기 내 번역"
    @Published var toast: String?
    @Published private(set) var lastCopy: CopyFeedback?
    @Published var detectedID: String?
    @Published var configuration: TranslationSession.Configuration?
    @Published var downloadConfiguration: TranslationSession.Configuration?
    @Published var languages = AppLanguage.common
    @Published var history: [TranslationRecord] = []
    @Published var shortcut: KeyboardShortcut { didSet { shortcut.save(to: defaults) } }
    @Published var shortcutError: String?
    @Published private(set) var sourceSelectionRequest: UUID?

    private let defaults: UserDefaults
    private var pending: Request?
    var activeRequestID: UUID? { pending?.id }
    private var generation = UUID()
    private var debounce: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private let speaker = AVSpeechSynthesizer()
    private var lastOutputTarget = "ko"
    private let historyURL: URL
    var onRequestShow: (() -> Void)?
    var onRequestClose: (() -> Void)?

    init(defaults: UserDefaults = .standard, historyURL: URL? = nil) {
        self.defaults = defaults
        self.sourceID = defaults.string(forKey: "source") ?? "auto"
        self.targetID = defaults.string(forKey: "target") ?? "ko"
        self.smartPair = defaults.object(forKey: "smartPair") as? Bool ?? true
        self.autoTranslate = defaults.object(forKey: "autoTranslate") as? Bool ?? true
        self.saveHistory = defaults.object(forKey: "saveHistory") as? Bool ?? false
        self.shortcut = KeyboardShortcut.load(from: defaults)
        self.historyURL = historyURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Baram/history.json")
        if let data = try? Data(contentsOf: self.historyURL), let records = try? JSONDecoder().decode([TranslationRecord].self, from: data) {
            history = Array(records.prefix(100))
        }
    }

    func loadLanguages() async {
        let supported = await LanguageAvailability().supportedLanguages
        let ids = Set(supported.map { $0.languageCode?.identifier ?? "" })
        let curated = AppLanguage.common.filter { ids.contains($0.locale.languageCode?.identifier ?? "") }
        let known = Set(curated.map { $0.locale.languageCode?.identifier ?? "" })
        let extra = supported.filter { !known.contains($0.languageCode?.identifier ?? "") }.map {
            let id = $0.minimalIdentifier
            return AppLanguage(id: id, name: AppLanguage.name(for: id), nativeName: Locale(identifier: id).localizedString(forLanguageCode: id) ?? id)
        }.sorted { $0.name < $1.name }
        if !curated.isEmpty { languages = curated + extra }
    }

    func inputEdited() {
        invalidate()
        guard autoTranslate, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, self?.autoTranslate == true else { return }
            self?.translate()
        }
    }

    func invalidate() {
        debounce?.cancel()
        generation = UUID()
        pending = nil
        cancelAutomaticSelection()
        configuration = nil
        downloadConfiguration = nil
        output = ""
        error = nil
        busy = false
        status = "기기 내 번역"
    }

    func pasteAndTranslate(selectSource: Bool = false, from pasteboard: NSPasteboard = .general) {
        page = .translate
        onRequestShow?()
        guard let text = PlainClipboard.read(from: pasteboard), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            invalidate()
            error = "클립보드에 텍스트가 없어요. 먼저 글을 복사해 주세요."
            return
        }
        input = text
        translate()
        // Clipboard selection belongs to the imported original, independent of
        // the asynchronous translation (including failures or unsupported text).
        if selectSource { sourceSelectionRequest = UUID() }
    }

    func translate() {
        debounce?.cancel()
        let text = input
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { invalidate(); return }
        let previousConfiguration = configuration
        invalidate()
        guard text.count <= 30000 else { error = "한 번에 30,000자까지 번역할 수 있어요. 원문을 나누어 주세요."; return }
        let id = UUID()
        generation = id
        let detected = sourceID == "auto" ? AppLanguage.detect(text) : sourceID
        detectedID = detected
        let target = AppLanguage.target(for: detected, preferred: targetID, smart: smartPair && sourceID == "auto")
        targetID = target
        lastOutputTarget = target
        if detected == target {
            output = text
            status = "같은 언어 · 원문 유지"
            return
        }
        let request = Request(id: id, text: text, source: sourceID == "auto" ? nil : sourceID, target: target)
        pending = request
        busy = true
        status = "번역 준비 중…"
        var config = TranslationSession.Configuration(
            source: request.source.map { Locale.Language(identifier: $0) },
            target: Locale.Language(identifier: target)
        )
        if #available(macOS 26.4, *) { config.preferredStrategy = .highFidelity }
        if let previousConfiguration, previousConfiguration.source == config.source, previousConfiguration.target == config.target {
            config = previousConfiguration
            config.invalidate()
        }
        configuration = config
    }

    func resolveTranslation() async {
        guard !Task.isCancelled, let request = pending, request.id == generation else { return }
        let resolvedSource = request.source ?? detectedID
        guard let resolvedSource else { downloadConfiguration = configuration; return }
        let source = Locale.Language(identifier: resolvedSource)
        let target = Locale.Language(identifier: request.target)
        let availability: LanguageAvailability
        if #available(macOS 26.4, *) { availability = LanguageAvailability(preferredStrategy: .highFidelity) }
        else { availability = LanguageAvailability() }
        let state = await availability.status(from: source, to: target)
        guard request.id == generation, !Task.isCancelled else { return }
        if state == .installed {
            let session: TranslationSession
            if #available(macOS 26.4, *) {
                session = TranslationSession(installedSource: source, target: target, preferredStrategy: .highFidelity)
            } else { session = TranslationSession(installedSource: source, target: target) }
            await execute(session, request: request, prepare: false)
        } else if state == .supported {
            status = "처음 사용하는 언어를 준비해 주세요"
            downloadConfiguration = configuration
        } else {
            busy = false
            status = "지원하지 않는 언어 조합"
            error = Self.message(for: TranslationError.unsupportedLanguagePairing)
        }
    }

    func run(_ session: TranslationSession, requestID: UUID?) async {
        guard !Task.isCancelled, let request = pending, request.id == generation, request.id == requestID else { return }
        await execute(session, request: request, prepare: request.source != nil)
    }

    private func execute(_ session: TranslationSession, request: Request, prepare: Bool) async {
        do {
            if prepare { try await session.prepareTranslation() }
            guard request.id == generation, !Task.isCancelled else { return }
            status = "번역 중…"
            let response = try await session.translate(request.text)
            guard request.id == generation, !Task.isCancelled else { return }
            completeTranslation(response, requestID: request.id)
        } catch {
            guard request.id == generation else { return }
            busy = false
            if error is CancellationError || Task.isCancelled {
                status = "번역 취소됨"
            } else {
                status = "번역을 완료하지 못했어요"
                self.error = Self.message(for: error)
            }
        }
    }

    func completeTranslation(_ response: TranslationSession.Response, requestID: UUID) {
        guard let request = pending, request.id == requestID, requestID == generation else { return }
        output = response.targetText
        detectedID = response.sourceLanguage.minimalIdentifier
        lastOutputTarget = request.target
        busy = false
        status = "기기 내 번역 완료"
        if saveHistory {
            history.removeAll { $0.source == request.text && $0.targetCode == request.target }
            history.insert(.init(source: request.text, target: response.targetText, sourceCode: detectedID ?? "auto", targetCode: request.target), at: 0)
            history = Array(history.prefix(100))
            persistHistory()
        }
    }

    func cancelAutomaticSelection() {
        sourceSelectionRequest = nil
    }

    static func message(for error: Error) -> String {
        switch error {
        case TranslationError.unsupportedSourceLanguage, TranslationError.unsupportedTargetLanguage, TranslationError.unsupportedLanguagePairing:
            return "이 언어 조합은 Apple 번역에서 지원하지 않아요. 원문 언어를 직접 선택하거나 다른 언어로 바꿔 주세요."
        case TranslationError.unableToIdentifyLanguage:
            return "언어를 감지하기 어려워요. 위에서 원문 언어를 직접 선택해 주세요."
        case TranslationError.notInstalled:
            return "번역 언어가 아직 준비되지 않았어요. 다시 번역을 눌러 언어 다운로드를 완료해 주세요."
        case TranslationError.nothingToTranslate:
            return "번역할 텍스트를 입력해 주세요."
        default:
            return "언어 다운로드 또는 번역에 실패했어요. 인터넷 연결을 확인한 뒤 다시 시도해 주세요. (\((error as NSError).code))"
        }
    }

    func selectSource(_ id: String) { sourceID = id; if !input.isEmpty { translate() } }
    func selectTarget(_ id: String) { targetID = id; smartPair = false; if !input.isEmpty { translate() } }
    func swap() {
        let previousSource = sourceID == "auto" ? (detectedID ?? "en") : sourceID
        sourceID = targetID
        targetID = previousSource
        smartPair = false
        if !output.isEmpty { input = output }
        translate()
    }
    func clear() { input = ""; detectedID = nil; invalidate() }
    func copy(_ text: String, source: Bool = false) {
        guard !text.isEmpty else { return }
        guard PlainClipboard.write(text) else { showToast("복사하지 못했어요. 다시 시도해 주세요."); return }
        notifyCopied(source: source)
    }
    func notifyCopied(source: Bool) {
        lastCopy = CopyFeedback(source: source)
        showToast("서식 없이 복사했어요")
    }
    func showToast(_ text: String) {
        toastTask?.cancel()
        toast = text
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
    func speak(_ text: String, source: Bool = false) {
        if speaker.isSpeaking { speaker.stopSpeaking(at: .immediate); return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: source ? (detectedID ?? sourceID) : lastOutputTarget)
        speaker.speak(utterance)
    }
    func restore(_ record: TranslationRecord) {
        invalidate()
        input = record.source
        output = record.target
        sourceID = record.sourceCode
        detectedID = record.sourceCode
        targetID = record.targetCode
        lastOutputTarget = record.targetCode
        page = .translate
        status = "기록에서 불러옴"
    }
    func clearHistory() { history = []; persistHistory() }
    private func persistHistory() {
        do {
            try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(history)
            try data.write(to: historyURL, options: .atomic)
        } catch { showToast("기록을 저장하지 못했어요") }
    }
}
