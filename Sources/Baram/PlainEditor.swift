import AppKit
import SwiftUI

struct PlainEditor: NSViewRepresentable {
    @Binding var text: String
    var editable = true
    var label: String
    var selectionRequest: UUID? = nil
    var onEdit: () -> Void = {}
    var onCopy: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = EditorScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let view = PlainTextView(frame: NSRect(x: 0, y: 0, width: 250, height: 240), textContainer: nil)
        view.delegate = context.coordinator
        view.onCopy = { [weak coordinator = context.coordinator] in coordinator?.parent.onCopy() }
        view.isEditable = editable
        view.isSelectable = true
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.drawsBackground = false
        view.font = .systemFont(ofSize: 15)
        view.textColor = .labelColor
        view.insertionPointColor = NSColor(BaramTheme.accentText)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        view.defaultParagraphStyle = paragraph
        view.selectedTextAttributes = [
            .backgroundColor: NSColor(BaramTheme.accent).withAlphaComponent(0.30),
            .foregroundColor: NSColor.labelColor
        ]
        view.textContainerInset = NSSize(width: 0, height: 4)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.minSize = NSSize(width: 0, height: 240)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.setAccessibilityLabel(label)
        scroll.documentView = view
        scroll.onWindowChange = { [weak coordinator = context.coordinator, weak view] window in
            guard let view else { return }
            coordinator?.observeWindow(window, for: view)
        }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? PlainTextView else { return }
        if view.string != text, !view.hasMarkedText() {
            let selected = view.selectedRange()
            view.string = text
            view.setSelectedRange(NSRange(location: min(selected.location, (text as NSString).length), length: 0))
            view.undoManager?.removeAllActions()
        }
        context.coordinator.selectResultIfRequested(in: view)
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        (scroll as? EditorScrollView)?.onWindowChange = nil
        coordinator.stopObserving()
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainEditor
        private var selectedRequest: UUID?
        private var scheduledRequest: UUID?
        private var scheduledText: String?
        private var windowObservers: [NSObjectProtocol] = []
        init(_ parent: PlainEditor) { self.parent = parent }
        deinit { windowObservers.forEach(NotificationCenter.default.removeObserver) }

        func observeWindow(_ window: NSWindow?, for view: NSTextView) {
            stopObserving()
            guard let window else { return }
            // A SwiftUI update can arrive before attachment or before the panel
            // becomes key. Retry when those conditions actually change.
            for (name, object) in [
                (NSWindow.didBecomeKeyNotification, window as AnyObject),
                (NSApplication.didBecomeActiveNotification, NSApplication.shared as AnyObject)
            ] {
                windowObservers.append(NotificationCenter.default.addObserver(
                    forName: name, object: object, queue: .main
                ) { [weak self, weak view] _ in
                    MainActor.assumeIsolated {
                        guard let view else { return }
                        self?.selectResultIfRequested(in: view)
                    }
                })
            }
            selectResultIfRequested(in: view)
        }

        func stopObserving() {
            windowObservers.forEach(NotificationCenter.default.removeObserver)
            windowObservers.removeAll()
            scheduledRequest = nil
            scheduledText = nil
        }

        func selectResultIfRequested(in view: NSTextView) {
            guard !parent.editable, let request = parent.selectionRequest,
                  request != selectedRequest, !parent.text.isEmpty else { return }
            let expectedText = parent.text
            guard scheduledRequest != request || scheduledText != expectedText else { return }
            scheduledRequest = request
            scheduledText = expectedText

            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, self.scheduledRequest == request,
                      self.scheduledText == expectedText else { return }
                self.scheduledRequest = nil
                self.scheduledText = nil
                guard let view, !self.parent.editable, !view.isEditable,
                      self.parent.selectionRequest == request, self.selectedRequest != request,
                      self.parent.text == expectedText, view.string == expectedText,
                      !view.hasMarkedText(), !view.isHiddenOrHasHiddenAncestor,
                      NSApplication.shared.isActive,
                      let window = view.window, window.isVisible, window.isKeyWindow,
                      window.makeFirstResponder(view) else { return }
                let range = NSRange(location: 0, length: (expectedText as NSString).length)
                view.setSelectedRange(range)
                view.scrollRangeToVisible(range)
                // Keep the token consumed across ordinary SwiftUI updates so
                // copying or selecting a smaller passage does not select all again.
                self.selectedRequest = request
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            if !view.hasMarkedText() { parent.onEdit() }
        }
    }
}

private final class EditorScrollView: NSScrollView {
    var onWindowChange: ((NSWindow?) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }

    override func layout() {
        super.layout()
        guard let textView = documentView as? NSTextView else { return }
        let area = contentSize
        textView.minSize = NSSize(width: 0, height: area.height)
        if textView.frame.width != area.width || textView.frame.height < area.height {
            textView.setFrameSize(NSSize(width: area.width, height: max(textView.frame.height, area.height)))
        }
    }
}
