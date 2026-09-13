import AppKit
import SwiftUI

extension Notification.Name {
    /// The current global chord remains reserved while its recorder has focus.
    static let baramRecordedShortcut = Notification.Name("local.baram.recordedShortcut")
}

enum ShortcutCaptureAction: Equatable {
    case cancel
    case invalid(String)
    case shortcut(KeyboardShortcut)

    static func from(event: NSEvent) -> ShortcutCaptureAction {
        if event.keyCode == 53 { return .cancel }
        if let shortcut = KeyboardShortcut(event: event) { return .shortcut(shortcut) }
        return .invalid(KeyboardShortcut.validationError(for: event) ?? "다른 키 조합을 눌러 주세요.")
    }
}

struct ShortcutRecorder: View {
    let shortcut: KeyboardShortcut
    let registrationError: String?
    let onCommit: (KeyboardShortcut) -> Bool
    let onRecordingChange: (Bool) -> Void
    @State private var recording = false
    @State private var inputError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("클립보드 번역 단축키").font(.system(size: 13, weight: .medium))
                    Text("어느 앱에서든 복사 후 눌러 주세요.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    inputError = nil
                    setRecording(!recording)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: recording ? "record.circle" : "keyboard")
                            .font(.system(size: 12))
                        Text(recording ? "키 조합 입력…" : shortcut.displayName)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(recording ? BaramTheme.accentText : Color.primary)
                    .frame(minWidth: 144).frame(height: 35)
                    .background(BaramTheme.raised, in: RoundedRectangle(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(recording ? BaramTheme.accentText : BaramTheme.stroke, lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                }
                .buttonStyle(BaramButtonStyle())
                .accessibilityLabel(recording ? "단축키 입력 취소" : "단축키 변경, 현재 \(shortcut.accessibilityLabel)")
                .accessibilityHint("누른 뒤 원하는 키 조합을 입력하세요. Escape 키로 취소합니다.")
                .help("눌러서 원하는 단축키로 변경")
                .background {
                    ShortcutCaptureHost(recording: recording, onAction: handle, onCancel: { setRecording(false) })
                        .allowsHitTesting(false)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(recording ? "⌘ · ⌃ · ⌥ 중 하나와 함께 키를 눌러 주세요. Esc로 취소합니다." : "단축키를 누르면 창을 열고 클립보드의 글을 번역합니다.")
                    .font(.system(size: 10)).foregroundStyle(recording ? BaramTheme.accentText : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("기본값 ⌘⇧I") {
                    setRecording(false)
                    inputError = nil
                    _ = onCommit(.commandShiftI)
                }
                .buttonStyle(.link).font(.system(size: 10))
                .disabled(shortcut == .commandShiftI && !recording && registrationError == nil)
                .help("기본 단축키로 되돌리기")
            }
            if let error = inputError ?? registrationError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("단축키 오류: \(error)")
            }
        }
        .onDisappear { setRecording(false) }
    }

    private func handle(_ action: ShortcutCaptureAction) {
        guard recording else { return }
        switch action {
        case .cancel:
            inputError = nil
            setRecording(false)
        case let .invalid(message):
            inputError = message
        case let .shortcut(candidate):
            inputError = nil
            if onCommit(candidate) { setRecording(false) }
        }
    }

    private func setRecording(_ value: Bool) {
        guard recording != value else { return }
        recording = value
        onRecordingChange(value)
    }
}

private struct ShortcutCaptureHost: NSViewRepresentable {
    let recording: Bool
    let onAction: (ShortcutCaptureAction) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutCaptureView { ShortcutCaptureView() }

    func updateNSView(_ view: ShortcutCaptureView, context: Context) {
        view.onAction = onAction
        view.onCancel = onCancel
        view.requestedRecording = recording
        // SwiftUI must finish attaching the host before it becomes first responder.
        DispatchQueue.main.async { [weak view] in view?.synchronizeRecording() }
    }

    static func dismantleNSView(_ view: ShortcutCaptureView, coordinator: ()) {
        view.requestedRecording = false
        view.stopRecording()
    }
}

private final class ShortcutCaptureView: NSView {
    var requestedRecording = false
    var onAction: ((ShortcutCaptureAction) -> Void)?
    var onCancel: (() -> Void)?
    private var capturing = false
    private var eventMonitor: Any?
    private var observations: [NSObjectProtocol] = []
    private weak var previousResponder: NSResponder?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil && capturing { cancelRecording() }
        else { DispatchQueue.main.async { [weak self] in self?.synchronizeRecording() } }
    }

    func synchronizeRecording() {
        guard requestedRecording else { stopRecording(); return }
        guard !capturing, let window else { return }
        guard window.isKeyWindow, NSApp.isActive else {
            requestedRecording = false
            onCancel?()
            return
        }
        previousResponder = window.firstResponder
        capturing = true
        guard window.makeFirstResponder(self) else { cancelRecording(); return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, self.capturing else { return event }
            guard event.window === self.window else { self.cancelRecording(); return event }
            if event.type == .keyDown {
                if !event.isARepeat { self.onAction?(ShortcutCaptureAction.from(event: event)) }
                return nil
            }
            if !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) { self.cancelRecording() }
            return event
        }
        let center = NotificationCenter.default
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            observations.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.cancelRecording()
            })
        }
        observations.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.cancelRecording()
        })
        observations.append(center.addObserver(forName: .baramRecordedShortcut, object: nil, queue: .main) { [weak self] note in
            guard let self, self.capturing, self.window?.isKeyWindow == true,
                  NSApp.isActive, let shortcut = note.object as? KeyboardShortcut else { return }
            self.onAction?(.shortcut(shortcut))
        })
    }

    func stopRecording(restoreFocus: Bool = true) {
        guard capturing else { return }
        capturing = false
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        observations.forEach(NotificationCenter.default.removeObserver)
        observations.removeAll()
        if restoreFocus, let window, window.firstResponder === self, window.isKeyWindow, NSApp.isActive {
            window.makeFirstResponder(previousResponder)
        }
        previousResponder = nil
    }

    private func cancelRecording() {
        guard capturing else { return }
        requestedRecording = false
        stopRecording()
        onCancel?()
    }

    override func resignFirstResponder() -> Bool {
        if capturing {
            requestedRecording = false
            stopRecording(restoreFocus: false)
            onCancel?()
        }
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard capturing else { super.keyDown(with: event); return }
        if !event.isARepeat { onAction?(ShortcutCaptureAction.from(event: event)) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard capturing else { return super.performKeyEquivalent(with: event) }
        if !event.isARepeat { onAction?(ShortcutCaptureAction.from(event: event)) }
        return true
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        observations.forEach(NotificationCenter.default.removeObserver)
    }
}
