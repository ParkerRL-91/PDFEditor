import PDFKit
import PDFStackKit
import SwiftUI

struct PDFKitRepresentable: NSViewRepresentable {
    let document: PDFDocument
    @Binding var currentSelection: PDFSelection?
    /// Called with a page and page-space point whenever the user clicks the PDFView,
    /// in the PDFView's own coordinate space -- no SwiftUI-to-AppKit conversion needed.
    /// Used by MarkupView to drive Note/Text placement and Erase hit-testing.
    var onPageClick: ((PDFPage, CGPoint) -> Void)?
    /// Called once the underlying PDFView exists, so a parent view can hold a
    /// reference for calls like `clearSelection()` after applying a markup action.
    var onViewCreated: ((PDFView) -> Void)?
    /// When true, dashed outlines are drawn over every detected text block
    /// (Edit Text mode's "what can I click?" affordance). Drawn in an overlay
    /// view, never as annotations, so arming the mode mutates nothing.
    var showTextBlockOutlines: Bool = false
    /// Called with the index of the page the PDFView scrolled to, so the
    /// thumbnail strip can keep its selection in sync with the canvas.
    var onPageChanged: ((Int) -> Void)?
    /// Called once, at mouse-up, with a completed non-empty text selection, so
    /// drag-to-apply markup tools can act on the just-finished selection.
    var onSelectionEnded: ((PDFSelection) -> Void)?

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.pageOverlayViewProvider = context.coordinator
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged),
            name: .PDFViewSelectionChanged,
            object: view
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged),
            name: .PDFViewPageChanged,
            object: view
        )
        let clickRecognizer = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleClick(_:))
        )
        view.addGestureRecognizer(clickRecognizer)
        // Deferred one runloop turn: makeNSView runs during SwiftUI's view update,
        // and onViewCreated writes into the parent's @State ("Modifying state during
        // view update" is undefined behavior -- SwiftUI can drop the write, which
        // would leave the parent's pdfView reference nil and silently break
        // clearSelection() and the annotationsChanged refresh that depend on it).
        let callback = onViewCreated
        DispatchQueue.main.async { callback?(view) }
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        context.coordinator.parent = self
        if nsView.document !== document {
            nsView.document = document
        }
        context.coordinator.refreshOverlays()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator, name: .PDFViewSelectionChanged, object: nsView)
        NotificationCenter.default.removeObserver(coordinator, name: .PDFViewPageChanged, object: nsView)
    }

    final class Coordinator: NSObject {
        var parent: PDFKitRepresentable
        init(_ parent: PDFKitRepresentable) { self.parent = parent }

        let overlays = NSMapTable<PDFPage, TextBlockOutlineView>(keyOptions: .weakMemory, valueOptions: .weakMemory)

        /// Bumped on every selection change so a scheduled mouse-up poll can tell
        /// whether it still describes the current selection (see selectionChanged).
        private var selectionGeneration = 0

        func refreshOverlays() {
            let enumerator = overlays.keyEnumerator()
            while let page = enumerator.nextObject() as? PDFPage {
                guard let overlay = overlays.object(forKey: page) else { continue }
                overlay.blockBounds = parent.showTextBlockOutlines
                    ? PDFTextBlockDetector.blocks(on: page).map(\.bounds)
                    : []
            }
        }

        @objc func selectionChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView else { return }
            parent.currentSelection = view.currentSelection
            // PDFKit has no "selection ended" callback: .PDFViewSelectionChanged
            // fires continuously as the drag extends the selection, never once at
            // release. Detect mouse-up by polling NSEvent.pressedMouseButtons, then
            // fire onSelectionEnded a single time. The generation counter discards
            // a stale scheduled poll once a newer selection change has superseded
            // it, so a given selection fires at most once.
            guard let selection = view.currentSelection,
                  (selection.string?.isEmpty == false) else { return }
            selectionGeneration &+= 1
            waitForSelectionMouseUp(selection, generation: selectionGeneration)
        }

        private func waitForSelectionMouseUp(_ selection: PDFSelection, generation: Int) {
            guard generation == selectionGeneration else { return }
            if NSEvent.pressedMouseButtons == 0 {
                parent.onSelectionEnded?(selection)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.waitForSelectionMouseUp(selection, generation: generation)
                }
            }
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView,
                  let page = view.currentPage,
                  let document = view.document else { return }
            let index = document.index(for: page)
            guard index != NSNotFound else { return }
            parent.onPageChanged?(index)
        }

        @objc func handleClick(_ recognizer: NSClickGestureRecognizer) {
            guard let pdfView = recognizer.view as? PDFView else { return }
            // NSClickGestureRecognizer fires on mouse-up regardless of whether the
            // mouse moved between down and up -- it has no built-in way to distinguish
            // "clicked" from "dragged to select text." PDFView's native text selection
            // is itself driven by that same mouse-down/drag/mouse-up sequence, so a user
            // dragging to select text (for Highlight/Underline/Strikethrough) would also
            // fire this handler on release. If a tool were armed at that moment (e.g.
            // Erase), onPageClick would fire at the drag's end point and could act on
            // whatever is under the cursor there -- not what the user intended. Bail out
            // whenever the drag produced a live text selection so a text-selection
            // gesture can never also be interpreted as a placement/erase click.
            guard pdfView.currentSelection == nil else { return }
            let viewPoint = recognizer.location(in: pdfView)
            guard let page = pdfView.page(for: viewPoint, nearest: true) else { return }
            let pagePoint = pdfView.convert(viewPoint, to: page)
            parent.onPageClick?(page, pagePoint)
        }
    }
}

extension PDFKitRepresentable.Coordinator: PDFPageOverlayViewProvider {
    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> NSView? {
        let overlay = TextBlockOutlineView()
        overlay.blockBounds = parent.showTextBlockOutlines
            ? PDFTextBlockDetector.blocks(on: page).map(\.bounds)
            : []
        overlays.setObject(overlay, forKey: page)
        return overlay
    }
}

/// Overlay installed by PDFPageOverlayViewProvider; PDFKit lays it out to match
/// the page, so drawing happens directly in page-space coordinates.
final class TextBlockOutlineView: NSView {
    var blockBounds: [CGRect] = [] {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !blockBounds.isEmpty else { return }
        for rect in blockBounds {
            let padded = rect.insetBy(dx: -3, dy: -3)
            let path = NSBezierPath(rect: padded)
            NSColor.systemBlue.withAlphaComponent(0.08).setFill()
            path.fill()
            path.setLineDash([4, 3], count: 2, phase: 0)
            path.lineWidth = 1
            NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
            path.stroke()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
