import SwiftUI
import Translation

struct TranslatorView: View {
    @ObservedObject var model: TranslatorModel
    var onShortcutChange: (KeyboardShortcut) -> Bool
    var onShortcutRecordingChange: (Bool) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copiedSource: Bool?
    @State private var copyReset: Task<Void, Never>?
    @State private var hoveredSource: Bool?
    private let mint = BaramTheme.accent
    private var gentle: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.16) }

    var body: some View {
        let requestID = model.activeRequestID
        return VStack(spacing: 0) {
            toolbar
            Group {
                switch model.page {
                case .translate: translation
                case .history: history
                case .settings: settings
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .padding(.horizontal, 12)
        .background(BaramTheme.background)
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(BaramTheme.stroke.opacity(0.65), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .tint(mint)
        .frame(minWidth: 560, minHeight: 420)
        .translationTask(model.downloadConfiguration) { session in await model.run(session, requestID: requestID) }
        .task(id: model.configuration) { await model.resolveTranslation() }
        .task { await model.loadLanguages() }
        .onChange(of: model.input) { copiedSource = nil }
        .onChange(of: model.output) { copiedSource = nil }
        .onChange(of: model.lastCopy) { if let event = model.lastCopy { copiedFeedback(source: event.source) } }
    }

    private var toolbar: some View {
        ZStack {
            HStack(spacing: 7) {
                Image(systemName: "wind").font(.system(size: 16, weight: .semibold)).foregroundStyle(BaramTheme.accentText)
                Text("바람").font(.system(size: 14, weight: .semibold))
            }.accessibilityElement(children: .combine)
            HStack(spacing: 5) {
                if model.page != .translate {
                    icon("chevron.left", "번역으로 돌아가기") { model.page = .translate }
                } else {
                    icon(model.pinned ? "pin.fill" : "pin", model.pinned ? "창 고정 해제" : "창 고정", active: model.pinned) {
                        model.pinned.toggle()
                    }
                    if model.pinned {
                        Text("고정됨").font(.system(size: 10, weight: .medium)).foregroundStyle(BaramTheme.accentText).transition(.opacity)
                    }
                }
                Spacer()
                icon("clock.arrow.circlepath", "번역 기록", active: model.page == .history) {
                    model.page = model.page == .history ? .translate : .history
                }
                icon("slider.horizontal.3", "설정", active: model.page == .settings) {
                    model.page = model.page == .settings ? .translate : .settings
                }
            }
        }
        .padding(.horizontal, 2).frame(height: 51)
        .animation(gentle, value: model.pinned)
    }

    private var translation: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                languagePicker(source: true)
                icon("arrow.left.arrow.right", "언어 바꾸기") { model.swap() }
                languagePicker(source: false)
            }
            HStack(spacing: 10) {
                textPane(source: true)
                textPane(source: false)
            }
        }
    }

    private func languagePicker(source: Bool) -> some View {
        let automatic = source && model.sourceID == "auto"
        let code = source ? model.sourceID : model.targetID
        return LanguagePickerButton(
            title: automatic ? "자동 감지" : AppLanguage.name(for: code),
            subtitle: automatic ? model.detectedID.map { AppLanguage.name(for: $0) } : nil,
            symbol: automatic ? "sparkle.magnifyingglass" : "character.bubble",
            languages: model.languages, selectedID: code, allowsAuto: source
        ) { id in
            if source { model.selectSource(id) } else { model.selectTarget(id) }
        }
        .accessibilityLabel(source ? "원문 언어" : "번역 언어")
    }

    private func textPane(source: Bool) -> some View {
        let text = source ? model.input : model.output
        let copied = copiedSource == source
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(source ? Color.secondary.opacity(0.45) : mint).frame(width: 5, height: 5)
                Text(source ? "원문" : "번역").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if !text.isEmpty {
                    Text("\(text.count)자").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                }
                if source && !text.isEmpty {
                    icon("xmark", "원문 지우기", small: true) { model.clear() }
                } else if !source && !model.output.isEmpty {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(BaramTheme.accentText)
                        .frame(width: 20, height: 22)
                }
            }.frame(height: 31)
            ZStack(alignment: .topLeading) {
                // Stable native editor identity preserves focus and partial selections.
                PlainEditor(text: source ? $model.input : $model.output, editable: source,
                            label: source ? "번역할 원문" : "번역 결과",
                            selectionRequest: source ? nil : model.resultSelectionRequest,
                            onEdit: { if source { model.inputEdited() } },
                            onCopy: { model.notifyCopied(source: source) })
                    .opacity(source || !model.output.isEmpty ? 1 : 0)
                    .allowsHitTesting(source || !model.output.isEmpty)
                if source && model.input.isEmpty {
                    sourcePlaceholder
                } else if !source && model.output.isEmpty {
                    resultPlaceholder
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 4) {
                icon("speaker.wave.2", source ? "원문 듣기" : "번역 듣기") { model.speak(text, source: source) }
                    .disabled(text.isEmpty)
                if source {
                    icon(copied ? "checkmark" : "doc.on.doc", "원문 서식 없이 복사", active: copied) { copy(source: true) }
                        .disabled(text.isEmpty)
                    Spacer(minLength: 2)
                    icon("clipboard", "클립보드 붙여넣고 번역") { model.pasteAndTranslate() }
                    Button { model.translate() } label: {
                        Image(systemName: "arrow.right").font(.system(size: 16, weight: .semibold)).frame(width: 35, height: 34)
                    }
                    .buttonStyle(BaramButtonStyle(emphasized: true))
                    .help("바로 번역  ⌘↩").accessibilityLabel("번역하기")
                    .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Spacer(minLength: 2)
                    Button { copy(source: false) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 12, weight: .medium))
                            Text(copied ? "복사됨" : "복사").font(.system(size: 12, weight: .medium))
                            if !copied { Text("⌘⇧C").font(.system(size: 10, design: .monospaced)).opacity(0.6) }
                        }
                        .foregroundStyle(copied ? BaramTheme.accentText : .primary)
                        .padding(.horizontal, 10).frame(height: 32).frame(minWidth: 102)
                    }
                    .buttonStyle(BaramButtonStyle())
                    .help("번역문 전체를 서식 없이 복사  ⌘⇧C").accessibilityLabel("번역문 서식 없이 복사")
                    .disabled(text.isEmpty)
                }
            }.frame(height: 49)
        }
        .padding(.horizontal, 13).padding(.top, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BaramTheme.surface, in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(hoveredSource == source ? mint.opacity(0.28) : BaramTheme.stroke, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .onHover { hovered in hoveredSource = hovered ? source : nil }
        .animation(gentle, value: hoveredSource == source)
    }

    private var sourcePlaceholder: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("붙여넣고,\n가볍게 번역하세요.")
                .font(.system(size: 21, weight: .medium)).tracking(-0.6).lineSpacing(3).foregroundStyle(.primary.opacity(0.74))
            Text("다른 앱에서 글을 복사한 뒤").font(.system(size: 12)).foregroundStyle(.secondary)
            HStack(spacing: 7) {
                keycap(model.shortcut.displayName)
                Text("누르면 바로 번역").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.padding(.top, 15).allowsHitTesting(false)
    }

    @ViewBuilder private var resultPlaceholder: some View {
        if model.busy {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text(model.status).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
                LoadingLines()
                Text("잠시만 기다려 주세요.").font(.system(size: 11)).foregroundStyle(.tertiary)
            }.padding(.top, 17).transition(.opacity)
        } else if let error = model.error {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "exclamationmark.bubble").font(.system(size: 22)).foregroundStyle(.orange)
                Text(error).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                Button { model.translate() } label: {
                    Label("다시 번역", systemImage: "arrow.clockwise").font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 11).frame(height: 30)
                }.buttonStyle(BaramButtonStyle())
            }.padding(.top, 15)
        } else {
            VStack(alignment: .leading, spacing: 13) {
                Image(systemName: "text.bubble").font(.system(size: 26, weight: .light)).foregroundStyle(mint.opacity(0.55))
                Text("다른 언어로,\n같은 마음을.").font(.system(size: 17, weight: .medium)).lineSpacing(4).foregroundStyle(.secondary)
                Text("번역이 끝나면 이곳에 나타나요.\n복사하면 언제나 순수 텍스트.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary).lineSpacing(4)
            }.padding(.top, 17).allowsHitTesting(false)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Group {
                if model.toast != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(BaramTheme.accentText) }
                else if model.shortcutError != nil || model.error != nil { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) }
                else { Image(systemName: "lock.shield").foregroundStyle(.secondary) }
            }.font(.system(size: 10))
            Text(footerText).lineLimit(1).font(.system(size: 10)).foregroundStyle(.secondary)
                .contentTransition(.opacity).animation(gentle, value: footerText)
            Spacer(minLength: 4)
            if model.page == .translate {
                Button {
                    model.smartPair.toggle()
                    if model.smartPair { model.sourceID = "auto" }
                    if !model.input.isEmpty { model.translate() }
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(model.smartPair ? mint : .secondary.opacity(0.4)).frame(width: 4, height: 4)
                        Text("한 ↔ 영 자동").font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(model.smartPair ? BaramTheme.accentText : .secondary).padding(.horizontal, 8).frame(height: 24)
                }.buttonStyle(BaramButtonStyle(compact: true))
                    .help("한국어는 영어로, 그 외 언어는 한국어로 자동 번역")
            }
        }.padding(.horizontal, 3).frame(height: 36)
    }

    private var footerText: String {
        if let toast = model.toast { return toast }
        if model.shortcutError != nil { return "단축키 충돌 · 설정에서 변경해 주세요" }
        if model.resultSelectionRequest != nil && !model.output.isEmpty { return "번역 완료 · ⌘C로 바로 복사" }
        if model.pinned && model.output.isEmpty && !model.busy { return "창이 고정되어 있어요" }
        return model.status
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                Text("설정").font(.system(size: 20, weight: .semibold))
                ShortcutRecorder(shortcut: model.shortcut, registrationError: model.shortcutError,
                                 onCommit: onShortcutChange, onRecordingChange: onShortcutRecordingChange)
                Divider()
                settingsToggle("입력하면 자동 번역", detail: "입력을 잠시 멈추면 번역합니다.", value: $model.autoTranslate)
                settingsToggle("한국어 ↔ 영어 자동 전환", detail: "자동 감지에서 한국어는 영어로, 그 외는 한국어로.", value: $model.smartPair)
                settingsToggle("번역 기록 저장", detail: "이 맥에 최근 100개만 저장합니다. 기본값은 꺼짐.", value: $model.saveHistory)
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    Label("Apple 내장 번역", systemImage: "lock.shield").font(.system(size: 12, weight: .medium))
                    Text("구독 · API 키 없이 기기에서 번역합니다. 처음 사용하는 언어는 macOS의 언어 다운로드가 필요할 수 있어요.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                    Text("복사 버튼과 ⌘C는 원문·번역문 모두 순수 텍스트만 복사합니다.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                HStack {
                    Text("바람 1.2 · 나만의 작은 번역기").font(.system(size: 10)).foregroundStyle(.tertiary)
                    Spacer()
                    Button("바람 종료") { NSApp.terminate(nil) }.controlSize(.small)
                }
            }.padding(16)
        }
    }
    private func settingsToggle(_ title: String, detail: String, value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.toggleStyle(.switch).controlSize(.small)
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("번역 기록").font(.system(size: 20, weight: .semibold))
                Spacer()
                if !model.history.isEmpty { Button("모두 지우기") { model.clearHistory() }.controlSize(.small) }
            }
            if model.history.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock").font(.system(size: 30)).foregroundStyle(.tertiary)
                    Text("아직 저장된 번역이 없어요.").font(.system(size: 13)).foregroundStyle(.secondary)
                    if !model.saveHistory { Button("번역 기록 저장 켜기") { model.saveHistory = true }.buttonStyle(.bordered) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.history) { item in
                            Button { model.restore(item) } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text("\(AppLanguage.name(for: item.sourceCode)) → \(AppLanguage.name(for: item.targetCode))")
                                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                                    Text(item.source).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                                    Text(item.target).font(.system(size: 13)).lineLimit(2)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
        }.padding(16)
    }
    private func icon(_ symbol: String, _ label: String, active: Bool = false, small: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: small ? 10 : 13, weight: .medium))
                .foregroundStyle(active ? BaramTheme.accentText : .secondary)
                .frame(width: small ? 22 : 30, height: small ? 22 : 30)
        }
        .buttonStyle(BaramButtonStyle(compact: true)).help(label).accessibilityLabel(label)
    }

    private func keycap(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(.horizontal, 8).frame(height: 25)
            .background(BaramTheme.raised, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(BaramTheme.stroke, lineWidth: 1))
    }

    private func copy(source: Bool) {
        model.copy(source ? model.input : model.output, source: source)
    }

    private func copiedFeedback(source: Bool) {
        copyReset?.cancel()
        withAnimation(gentle) { copiedSource = source }
        copyReset = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }
            withAnimation(gentle) { copiedSource = nil }
        }
    }
}

private struct LoadingLines: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var soft = false
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 11) {
                ForEach([0.92, 0.76, 0.84, 0.48], id: \.self) { fraction in
                    Capsule().fill(BaramTheme.accent.opacity(0.10))
                        .frame(width: geometry.size.width * fraction, height: 7)
                }
            }.opacity(soft ? 0.45 : 1)
        }
        .frame(height: 63)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { soft = true }
        }
    }
}
