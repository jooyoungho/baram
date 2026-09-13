import AppKit

/// Every clipboard boundary uses Unicode text, so formatting from Notion and
/// other rich editors cannot accidentally travel through Baram.
@MainActor
enum PlainClipboard {
    static func read(from pasteboard: NSPasteboard = .general) -> String? {
        if let string = pasteboard.string(forType: .string) {
            return string
        }

        let richTypes: [(NSPasteboard.PasteboardType, NSAttributedString.DocumentType)] = [
            (.rtf, .rtf),
            (.html, .html)
        ]
        for (pasteboardType, documentType) in richTypes {
            guard let data = pasteboard.data(forType: pasteboardType),
                  let attributed = try? NSAttributedString(
                    data: data,
                    options: [.documentType: documentType],
                    documentAttributes: nil
                  ) else { continue }
            return attributed.string
        }
        return nil
    }

    @discardableResult
    static func write(_ text: String, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}

/// An ordinary, selectable AppKit editor with native selection and undo support.
/// Both source and translated text use this view, including read-only results.
@MainActor
final class PlainTextView: NSTextView {
    private var ownedTextStorage: NSTextStorage?
    var onCopy: (() -> Void)?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        // NSTextView's designated initializer does not create a text system
        // when its container is nil. Without one it can receive focus but all
        // typing and paste operations silently disappear.
        let storage: NSTextStorage?
        let resolvedContainer: NSTextContainer
        if let container {
            storage = nil
            resolvedContainer = container
        } else {
            let newStorage = NSTextStorage()
            let layoutManager = NSLayoutManager()
            let newContainer = NSTextContainer(containerSize: NSSize(
                width: max(frameRect.width, 1),
                height: CGFloat.greatestFiniteMagnitude
            ))
            newContainer.widthTracksTextView = true
            newStorage.addLayoutManager(layoutManager)
            layoutManager.addTextContainer(newContainer)
            storage = newStorage
            resolvedContainer = newContainer
        }
        super.init(frame: frameRect, textContainer: resolvedContainer)
        ownedTextStorage = storage
        configurePlainText()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configurePlainText()
    }

    private func configurePlainText() {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
    }

    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.string]
    }

    override func copy(_ sender: Any?) {
        if writeSelection(to: .general, types: [.string]) { onCopy?() }
    }

    override func writeSelection(to pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard types.contains(.string) else { return false }
        let content = string as NSString
        let selections = selectedRanges.map(\.rangeValue).filter {
            $0.location != NSNotFound && $0.length > 0 && NSMaxRange($0) <= content.length
        }
        guard !selections.isEmpty else { return false }
        return PlainClipboard.write(
            selections.map { content.substring(with: $0) }.joined(separator: "\n"),
            to: pasteboard
        )
    }

    override func cut(_ sender: Any?) {
        guard isEditable, selectedRanges.contains(where: { $0.rangeValue.length > 0 }) else { return }
        copy(sender)
        // Use the text system instead of assigning `string`, preserving undo,
        // change notifications, and the behavior of multiple selected ranges.
        delete(sender)
    }

    override func paste(_ sender: Any?) {
        guard isEditable, let text = PlainClipboard.read() else { return }
        insertText(text, replacementRange: selectedRange())
    }

    override func pasteAsRichText(_ sender: Any?) {
        paste(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        paste(sender)
    }
}
