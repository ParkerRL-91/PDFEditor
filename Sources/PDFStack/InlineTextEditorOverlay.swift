import AppKit
import PDFKit
import PDFStackKit
import SwiftUI

/// A bare NSTextView (no scroll view) mounted directly over the canvas so text
/// is typed and edited where it lands, at the PDFView's current zoom. The
/// container passes clicks outside the editor straight through to the PDFView,
/// so the existing page-click recognizer still fires (and commits the edit).
struct InlineTextEditorOverlay: NSViewRepresentable {
    @ObservedObject var session: MarkupSession
    let pdfView: PDFView
    let onCommit: () -> Void
    let onCancel: () -> Void

    /// The editor's page-space rect. Fixed per edit (does not track typing):
    /// new text uses a default box centered on the click point (matching how
    /// `addFreeText` places its bounds), edits use the target's bounds.
    static func pageRect(for edit: InlineEdit) -> CGRect {
        switch edit.kind {
        case .newText(let point):
            let lineHeight = NSLayoutManager().defaultLineHeight(for: edit.style.font)
            let height = ceil(lineHeight) + 8
            return CGRect(x: point.x, y: point.y - height / 2, width: 260, height: height)
        case .editBlock(let block):
            return block.bounds
        case .editFreeText(let annotation):
            return annotation.bounds
        }
    }

    func makeNSView(context: Context) -> NSView {
        let container = InlineEditorContainerView()
        let textView = InlineNSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.white.withAlphaComponent(0.95)
        textView.textContainerInset = NSSize(width: 3, height: 3)
        textView.wantsLayer = true
        textView.layer?.borderWidth = 2
        textView.layer?.borderColor = NSColor(hex: 0x3F91BC).cgColor
        textView.layer?.cornerRadius = 2
        textView.onCommit = { [weak coordinator = context.coordinator] in coordinator?.parent.onCommit() }
        textView.onCancel = { [weak coordinator = context.coordinator] in coordinator?.parent.onCancel() }
        if let edit = session.inlineEdit {
            textView.string = edit.text
        }

        container.addSubview(textView)
        container.editor = textView

        context.coordinator.container = container
        context.coordinator.textView = textView
        context.coordinator.pdfView = pdfView
        context.coordinator.applyStyle()
        context.coordinator.startObserving()

        container.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.updateFrame()
            coordinator?.focusEditor()
        }
        DispatchQueue.main.async {
            context.coordinator.updateFrame()
            context.coordinator.focusEditor()
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        // Live-apply style/frame from the (possibly inspector-mutated) edit.
        // Never re-set the text here -- the NSTextView is the source of truth
        // for text (see textDidChange), so pushing session.text back would fight
        // the cursor.
        context.coordinator.applyStyle()
        context.coordinator.updateFrame()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InlineTextEditorOverlay
        weak var container: NSView?
        weak var textView: NSTextView?
        weak var pdfView: PDFView?
        private var observers: [NSObjectProtocol] = []

        init(_ parent: InlineTextEditorOverlay) { self.parent = parent }

        func startObserving() {
            guard let pdfView else { return }
            let nc = NotificationCenter.default
            // Rescale + reposition when the user zooms.
            observers.append(nc.addObserver(forName: .PDFViewScaleChanged, object: pdfView, queue: .main) { [weak self] _ in
                self?.applyStyle()
                self?.updateFrame()
            })
            // Reposition when the page scrolls under the editor.
            if let clip = pdfView.firstDescendantScrollView?.contentView {
                clip.postsBoundsChangedNotifications = true
                observers.append(nc.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                    self?.updateFrame()
                })
            }
        }

        func stopObserving() {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()
        }

        /// Positions the editor over its page rect in view space, going through
        /// the shared window so it works regardless of each view's flip state.
        func updateFrame() {
            guard let container, let pdfView, let textView,
                  let edit = parent.session.inlineEdit else { return }
            let pageRect = InlineTextEditorOverlay.pageRect(for: edit)
            let inPDFView = pdfView.convert(pageRect, from: edit.page)
            textView.frame = container.convert(inPDFView, from: pdfView)
        }

        /// Scales the editor font by the PDFView's zoom so on-page text is WYSIWYG.
        func applyStyle() {
            guard let textView, let pdfView, let edit = parent.session.inlineEdit else { return }
            let base = edit.style.font
            let scaled = NSFont(descriptor: base.fontDescriptor, size: base.pointSize * pdfView.scaleFactor) ?? base
            textView.font = scaled
            textView.textColor = edit.style.color
            textView.alignment = edit.style.alignment
        }

        func focusEditor() {
            guard let textView, textView.window != nil else { return }
            textView.window?.makeFirstResponder(textView)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.session.inlineEdit?.text = textView.string
        }
    }
}

/// Hosts the editor and lets clicks outside it fall through to the PDFView below
/// (so the page-click recognizer commits the edit).
final class InlineEditorContainerView: NSView {
    weak var editor: NSView?
    var onLayout: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let editor else { return nil }
        let local = convert(point, from: superview)
        return editor.frame.contains(local) ? super.hitTest(point) : nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onLayout?()
    }
}

/// NSTextView that maps Cmd+Return to commit and Esc to cancel.
final class InlineNSTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // keyCode 36 is Return; with Command it commits the edit.
        if event.modifierFlags.contains(.command), event.keyCode == 36 {
            onCommit?()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

extension NSView {
    /// First NSScrollView in the subtree (PDFView hosts its scroll view privately).
    var firstDescendantScrollView: NSScrollView? {
        for subview in subviews {
            if let scrollView = subview as? NSScrollView { return scrollView }
            if let found = subview.firstDescendantScrollView { return found }
        }
        return nil
    }
}
