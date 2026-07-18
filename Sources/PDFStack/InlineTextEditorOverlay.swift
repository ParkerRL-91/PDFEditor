import AppKit
import PDFKit
import PDFStackKit
import SwiftUI

/// A bare NSTextView (no scroll view) mounted directly over the canvas so text
/// is typed and edited where it lands, at the PDFView's current zoom. The
/// container passes clicks outside the editor (and its resize handles) straight
/// through to the PDFView, so the existing page-click recognizer still fires
/// (and commits the edit).
struct InlineTextEditorOverlay: NSViewRepresentable {
    @ObservedObject var session: MarkupSession
    let pdfView: PDFView
    let onCommit: () -> Void
    let onCancel: () -> Void

    /// The editor's page-space rect. A resized/auto-grown edit carries an
    /// explicit `pageRectOverride`; otherwise new text uses a default box
    /// centered on the click point (matching how `addFreeText` places its
    /// bounds) and edits use the target's bounds.
    static func pageRect(for edit: InlineEdit) -> CGRect {
        if let override = edit.pageRectOverride { return override }
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
        // We drive the frame ourselves; keep the text container tall so layout
        // (and thus usedRect) reflects the full content height even when the box
        // is currently shorter than the text, which is what auto-grow measures.
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.size = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.onCommit = { [weak coordinator = context.coordinator] in coordinator?.parent.onCommit() }
        textView.onCancel = { [weak coordinator = context.coordinator] in coordinator?.parent.onCancel() }
        if let edit = session.inlineEdit {
            textView.string = edit.text
        }

        container.addSubview(textView)
        container.editor = textView

        // Four corner resize handles, layered above the editor so clicks on them
        // are captured (not passed through to the PDFView).
        var handles: [ResizeHandleView] = []
        for corner in ResizeHandleView.Corner.allCases {
            let handle = ResizeHandleView(corner: corner)
            handle.onDrag = { [weak coordinator = context.coordinator] corner, point, phase in
                coordinator?.handleDrag(corner: corner, to: point, phase: phase)
            }
            container.addSubview(handle)
            handles.append(handle)
        }
        container.handles = handles

        context.coordinator.container = container
        context.coordinator.textView = textView
        context.coordinator.pdfView = pdfView
        context.coordinator.handles = handles
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
        weak var container: InlineEditorContainerView?
        weak var textView: NSTextView?
        weak var pdfView: PDFView?
        var handles: [ResizeHandleView] = []
        private var observers: [NSObjectProtocol] = []
        private var isDragging = false

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
        /// the shared window so it works regardless of each view's flip state,
        /// then repositions the handles and grows the box if the content needs
        /// more height.
        func updateFrame() {
            guard let container, let pdfView, let textView,
                  let edit = parent.session.inlineEdit else { return }
            let pageRect = InlineTextEditorOverlay.pageRect(for: edit)
            let inPDFView = pdfView.convert(pageRect, from: edit.page)
            textView.frame = container.convert(inPDFView, from: pdfView)
            positionHandles()
            autoGrowToFit()
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

        /// Measures the laid-out content height (view space) and, if it exceeds
        /// the current box, grows the box DOWNWARD -- top-left (minX, maxY in
        /// page space) stays put while minY drops. Only ever grows, and only
        /// when the delta is meaningful, so it never fights the user's drag or
        /// loops against its own `setInlineRect`.
        func autoGrowToFit() {
            guard let textView, let pdfView, let container,
                  let edit = parent.session.inlineEdit,
                  pdfView.scaleFactor > 0,
                  let neededView = contentHeightViewSpace() else { return }
            let currentView = textView.frame.height
            guard neededView > currentView + 0.5 else { return }

            let neededPage = neededView / pdfView.scaleFactor
            var rect = InlineTextEditorOverlay.pageRect(for: edit)
            let maxY = rect.maxY
            rect.size.height = neededPage
            rect.origin.y = maxY - neededPage
            parent.session.setInlineRect(rect)

            // Apply the new frame directly rather than re-entering updateFrame()
            // (which would call autoGrowToFit again); the @Published write above
            // schedules one more pass that will find nothing left to grow.
            let inPDFView = pdfView.convert(rect, from: edit.page)
            textView.frame = container.convert(inPDFView, from: pdfView)
            positionHandles()
        }

        /// Content height in view space: the layout manager's used rect plus the
        /// text container's vertical inset on both edges.
        private func contentHeightViewSpace() -> CGFloat? {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return nil }
            layoutManager.ensureLayout(for: textContainer)
            let used = layoutManager.usedRect(for: textContainer)
            return ceil(used.height) + textView.textContainerInset.height * 2
        }

        /// One line of the scaled font plus insets, used as the minimum box
        /// height when dragging.
        private func minLineHeightViewSpace() -> CGFloat {
            guard let textView, let font = textView.font else { return 20 }
            return ceil(NSLayoutManager().defaultLineHeight(for: font)) + textView.textContainerInset.height * 2
        }

        func positionHandles() {
            guard let textView else { return }
            let frame = textView.frame
            let size: CGFloat = 10
            func place(_ handle: ResizeHandleView?, at point: NSPoint) {
                handle?.frame = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
            }
            for handle in handles {
                switch handle.corner {
                case .bottomLeft: place(handle, at: NSPoint(x: frame.minX, y: frame.minY))
                case .bottomRight: place(handle, at: NSPoint(x: frame.maxX, y: frame.minY))
                case .topLeft: place(handle, at: NSPoint(x: frame.minX, y: frame.maxY))
                case .topRight: place(handle, at: NSPoint(x: frame.maxX, y: frame.maxY))
                }
            }
        }

        /// Resizes the editor by moving the dragged corner while anchoring the
        /// opposite corner, enforcing a minimum size, then records the new box in
        /// page space. Text reflows to the new width automatically.
        func handleDrag(corner: ResizeHandleView.Corner, to point: NSPoint, phase: ResizeHandleView.DragPhase) {
            switch phase {
            case .began: isDragging = true
            case .ended: isDragging = false; return
            case .changed: break
            }
            guard let container, let textView, let pdfView,
                  let edit = parent.session.inlineEdit else { return }

            let frame = textView.frame
            let anchor: NSPoint
            switch corner {
            case .bottomLeft: anchor = NSPoint(x: frame.maxX, y: frame.maxY)
            case .bottomRight: anchor = NSPoint(x: frame.minX, y: frame.maxY)
            case .topLeft: anchor = NSPoint(x: frame.maxX, y: frame.minY)
            case .topRight: anchor = NSPoint(x: frame.minX, y: frame.minY)
            }

            let minW: CGFloat = 40
            let minH = minLineHeightViewSpace()
            var dragged = point
            if abs(dragged.x - anchor.x) < minW {
                dragged.x = anchor.x + (dragged.x >= anchor.x ? minW : -minW)
            }
            if abs(dragged.y - anchor.y) < minH {
                dragged.y = anchor.y + (dragged.y >= anchor.y ? minH : -minH)
            }

            let newFrame = CGRect(
                x: min(anchor.x, dragged.x),
                y: min(anchor.y, dragged.y),
                width: abs(dragged.x - anchor.x),
                height: abs(dragged.y - anchor.y)
            )
            textView.frame = newFrame
            positionHandles()

            let inPDFView = pdfView.convert(newFrame, from: container)
            let pageRect = pdfView.convert(inPDFView, to: edit.page)
            parent.session.setInlineRect(pageRect)
        }

        func focusEditor() {
            guard let textView, textView.window != nil else { return }
            textView.window?.makeFirstResponder(textView)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.session.inlineEdit?.text = textView.string
            autoGrowToFit()
        }
    }
}

/// Hosts the editor and its resize handles, letting clicks outside all of them
/// fall through to the PDFView below (so the page-click recognizer commits the
/// edit).
final class InlineEditorContainerView: NSView {
    weak var editor: NSView?
    var handles: [NSView] = []
    var onLayout: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        for handle in handles where handle.frame.contains(local) {
            return super.hitTest(point)
        }
        guard let editor else { return nil }
        return editor.frame.contains(local) ? super.hitTest(point) : nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onLayout?()
    }
}

/// A small corner handle that reports drag geometry (in container coordinates)
/// back to the overlay's coordinator.
final class ResizeHandleView: NSView {
    enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }
    enum DragPhase { case began, changed, ended }

    let corner: Corner
    var onDrag: ((Corner, NSPoint, DragPhase) -> Void)?

    init(corner: Corner) {
        self.corner = corner
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.borderWidth = 1.5
        layer?.borderColor = NSColor(hex: 0x3F91BC).cgColor
        layer?.cornerRadius = 2
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func containerPoint(for event: NSEvent) -> NSPoint {
        superview?.convert(event.locationInWindow, from: nil) ?? .zero
    }

    override func mouseDown(with event: NSEvent) { onDrag?(corner, containerPoint(for: event), .began) }
    override func mouseDragged(with event: NSEvent) { onDrag?(corner, containerPoint(for: event), .changed) }
    override func mouseUp(with event: NSEvent) { onDrag?(corner, containerPoint(for: event), .ended) }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
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
