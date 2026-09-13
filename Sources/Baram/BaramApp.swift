import AppKit
import SwiftUI
import Carbon

@main
struct BaramApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class TranslatorPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onTranslate: (() -> Void)?
    var onCopyResult: (() -> Void)?
    var isRecordingShortcut = false
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isRecordingShortcut { return false }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        if modifiers == .command, event.keyCode == 36 { onTranslate?(); return true }
        if modifiers == [.command, .shift], event.keyCode == UInt16(kVK_ANSI_C) || event.charactersIgnoringModifiers?.lowercased() == "c" { onCopyResult?(); return true }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = TranslatorModel()
    private let hotKey = GlobalHotKey()
    private var statusItem: NSStatusItem!
    private var panel: TranslatorPanel!
    private var resignObserver: NSObjectProtocol?
    private var transitionTimer: Timer?
    private var transitionGeneration: UInt = 0
    private var wantsPanelVisible = false
    private var isPositioningPanel = false
    private let panelWidthKey = "panelContentWidth"
    private let panelHeightKey = "panelContentHeight"

    func applicationDidFinishLaunching(_ notification: Notification) {
        createMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "바람 번역")
            button.image?.isTemplate = true
            button.toolTip = "바람 · 클립보드 번역 \(model.shortcut.title)"
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        let savedWidth = UserDefaults.standard.double(forKey: panelWidthKey)
        let savedHeight = UserDefaults.standard.double(forKey: panelHeightKey)
        let contentSize = NSSize(
            width: savedWidth >= 560 ? min(savedWidth, 1100) : 600,
            height: savedHeight >= 420 ? min(savedHeight, 900) : 460
        )
        panel = TranslatorPanel(contentRect: NSRect(origin: .zero, size: contentSize), styleMask: [.titled, .fullSizeContentView, .resizable], backing: .buffered, defer: false)
        panel.title = "바람"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentMinSize = NSSize(width: 560, height: 420)
        panel.contentMaxSize = NSSize(width: 1100, height: 900)
        panel.delegate = self
        panel.contentViewController = NSHostingController(rootView: TranslatorView(
            model: model,
            onShortcutChange: { [weak self] shortcut in self?.registerShortcut(shortcut) ?? false },
            onShortcutRecordingChange: { [weak self] recording in
                self?.hotKey.isSuspended = recording
                self?.panel.isRecordingShortcut = recording
            }
        ))
        panel.setContentSize(contentSize)
        panel.onEscape = { [weak self] in self?.hidePanel() }
        panel.onTranslate = { [weak self] in self?.model.translate() }
        panel.onCopyResult = { [weak self] in guard let self else { return }; self.model.copy(self.model.output) }
        model.onRequestShow = { [weak self] in self?.showPanel() }
        model.onRequestClose = { [weak self] in self?.hidePanel() }
        hotKey.onPressed = { [weak self] in self?.model.pasteAndTranslate(selectSource: true) }
        hotKey.onRecordedShortcut = { shortcut in
            NotificationCenter.default.post(name: .baramRecordedShortcut, object: shortcut)
        }
        registerShortcut()
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.model.pinned, !self.model.busy else { return }
                self.hidePanel()
            }
        }
        showPanel()
    }

    @discardableResult
    func registerShortcut(_ requested: KeyboardShortcut? = nil) -> Bool {
        let candidate = requested ?? model.shortcut
        guard hotKey.register(candidate) else {
            model.shortcutError = hotKey.lastError ?? "단축키를 등록하지 못했어요. 다른 조합을 선택해 주세요."
            return false
        }
        model.shortcut = candidate
        model.shortcutError = nil
        statusItem.button?.toolTip = "바람 · 클립보드 번역 \(model.shortcut.title)"
        return true
    }

    @objc private func togglePanel() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "클립보드 번역", action: #selector(translateClipboard), keyEquivalent: "").target = self
            menu.addItem(withTitle: "설정…", action: #selector(showSettings), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "바람 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            statusItem.button?.highlight(wantsPanelVisible)
            return
        }
        if wantsPanelVisible { hidePanel() } else { showPanel() }
    }

    private func showPanel() {
        if wantsPanelVisible, panel.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let wasVisible = panel.isVisible
        wantsPanelVisible = true
        cancelPanelTransition()
        statusItem.button?.highlight(true)

        let targetFrame = anchoredPanelFrame()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var initialFrame = targetFrame
        if wasVisible {
            initialFrame.origin = panel.frame.origin
        } else if !reduceMotion {
            // Settle down from the menu bar without delaying keyboard input.
            initialFrame.origin.y += 8
        }
        isPositioningPanel = true
        panel.setFrame(initialFrame, display: false)
        isPositioningPanel = false
        if !wasVisible { panel.alphaValue = reduceMotion ? 1 : 0 }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if reduceMotion {
            positionPanel(at: targetFrame.origin)
            panel.alphaValue = 1
        } else {
            animatePanel(toAlpha: 1, origin: targetFrame.origin, duration: 0.18)
        }
    }

    private func hidePanel() {
        model.cancelAutomaticSelection()
        guard wantsPanelVisible else { return }
        wantsPanelVisible = false
        cancelPanelTransition()
        statusItem.button?.highlight(false)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || !panel.isVisible {
            panel.orderOut(nil)
            panel.alphaValue = 1
        } else {
            animatePanel(toAlpha: 0, origin: panel.frame.origin, duration: 0.12) { [weak self] in
                guard let self, !self.wantsPanelVisible else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        }
    }

    private func anchoredPanelFrame() -> NSRect {
        guard let screen = statusItem.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            return panel.frame
        }
        let safeFrame = screen.visibleFrame.insetBy(dx: 10, dy: 8)
        var frame = panel.frame
        frame.size.width = min(frame.width, safeFrame.width)
        frame.size.height = min(frame.height, safeFrame.height)
        let anchor = statusItem.button?.window?.frame.midX ?? safeFrame.maxX - 70
        frame.origin = NSPoint(
            x: min(max(anchor - frame.width / 2, safeFrame.minX), safeFrame.maxX - frame.width),
            y: safeFrame.maxY - frame.height
        )
        return frame
    }

    private func cancelPanelTransition() {
        transitionGeneration &+= 1
        transitionTimer?.invalidate()
        transitionTimer = nil
    }

    /// A cancellable transition keeps rapid menu clicks and shortcut presses from
    /// allowing an old close completion to hide a freshly reopened panel.
    private func animatePanel(toAlpha: CGFloat, origin: NSPoint, duration: TimeInterval, completion: (() -> Void)? = nil) {
        let generation = transitionGeneration
        let startAlpha = panel.alphaValue
        let startOrigin = panel.frame.origin
        let startedAt = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.transitionGeneration == generation else { timer.invalidate(); return }
                let progress = min((ProcessInfo.processInfo.systemUptime - startedAt) / duration, 1)
                let eased = CGFloat(1 - pow(1 - progress, 3))
                self.panel.alphaValue = startAlpha + (toAlpha - startAlpha) * eased
                self.positionPanel(at: NSPoint(
                    x: startOrigin.x + (origin.x - startOrigin.x) * eased,
                    y: startOrigin.y + (origin.y - startOrigin.y) * eased
                ))
                if progress >= 1 {
                    timer.invalidate()
                    self.transitionTimer = nil
                    completion?()
                }
            }
        }
        transitionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func windowWillMove(_ notification: Notification) {
        guard !isPositioningPanel else { return }
        finishOpeningForInteraction()
    }

    private func positionPanel(at origin: NSPoint) {
        isPositioningPanel = true
        panel.setFrameOrigin(origin)
        isPositioningPanel = false
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        finishOpeningForInteraction()
    }

    private func finishOpeningForInteraction() {
        guard wantsPanelVisible else { return }
        cancelPanelTransition()
        panel.alphaValue = 1
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        // Store only dimensions, never clipboard contents or window position.
        let size = panel.contentRect(forFrameRect: panel.frame).size
        UserDefaults.standard.set(size.width, forKey: panelWidthKey)
        UserDefaults.standard.set(size.height, forKey: panelHeightKey)
    }
    @objc private func translateClipboard() { model.pasteAndTranslate() }
    @objc private func showSettings() { model.page = .settings; showPanel() }
    @objc private func showHistory() { model.page = .history; showPanel() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPanel(); return true }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hidePanel(); return false }
    func applicationWillTerminate(_ notification: Notification) { cancelPanelTransition(); hotKey.unregister() }

    private func createMenu() {
        let root = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "바람 설정…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "바람 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        root.addItem(appItem)
        let editItem = NSMenuItem(title: "편집", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "편집")
        for (title, selector, key) in [
            ("실행 취소", Selector(("undo:")), "z"),
            ("오려두기", #selector(NSText.cut(_:)), "x"),
            ("복사", #selector(NSText.copy(_:)), "c"),
            ("붙여넣기", #selector(NSText.paste(_:)), "v"),
            ("모두 선택", #selector(NSText.selectAll(_:)), "a")
        ] { edit.addItem(withTitle: title, action: selector, keyEquivalent: key) }
        let redo = NSMenuItem(title: "다시 실행", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.insertItem(redo, at: 1)
        editItem.submenu = edit
        root.addItem(editItem)
        NSApp.mainMenu = root
    }
}
