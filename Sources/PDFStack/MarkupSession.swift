import AppKit
import PDFKit
import PDFStackKit
import SwiftUI

enum MarkupTool: CaseIterable {
    case highlight, underline, strike, note, text, editText, erase

    var label: String {
        switch self {
        case .highlight: return "Highlight"
        case .underline: return "Underline"
        case .strike: return "Strike"
        case .note: return "Note"
        case .text: return "Text"
        case .editText: return "Edit Text"
        case .erase: return "Erase"
        }
    }

    var symbol: String {
        switch self {
        case .highlight: return "highlighter"
        case .underline: return "underline"
        case .strike: return "strikethrough"
        case .note: return "note.text"
        case .text: return "textformat"
        case .editText: return "pencil.line"
        case .erase: return "eraser"
        }
    }

    /// Divider grouping in the toolbar: 0 = markup, 1 = placement, 2 = erase.
    var group: Int {
        switch self {
        case .highlight, .underline, .strike: return 0
        case .note, .text, .editText: return 1
        case .erase: return 2
        }
    }
}

struct AnnotationEntry: Identifiable {
    let id: ObjectIdentifier
    let annotation: PDFAnnotation
    let page: PDFPage
    let title: String
    let subtitle: String
    let indicatorColor: NSColor
    let isSquareIndicator: Bool
}

/// An in-progress on-page text edit. Mounted as a live NSTextView over the
/// canvas while non-nil so the user types directly where the text will land,
/// instead of in a popover.
struct InlineEdit {
    enum Kind {
        /// A brand-new text box being placed at the clicked page point.
        case newText(pagePoint: CGPoint)
        /// An existing detected text block being visually replaced.
        case editBlock(TextBlock)
        /// An existing FreeText annotation being re-edited in place.
        case editFreeText(PDFAnnotation)
    }
    let kind: Kind
    let page: PDFPage
    var text: String
    var style: TextStyle
    /// The editor's box in page space, written by drag-resize and auto-grow.
    /// When nil, the box falls back to its kind-based default (see
    /// `InlineTextEditorOverlay.pageRect(for:)`).
    var pageRectOverride: CGRect?
}

final class MarkupSession: ObservableObject {
    @Published var activeTool: MarkupTool = .highlight
    @Published var activeSwatchID: String
    @Published var opacity: Double = 0.8
    @Published var currentPageIndex: Int = 0
    @Published var annotations: [AnnotationEntry] = []
    @Published var selectedAnnotationID: ObjectIdentifier?

    /// The active on-page text edit, or nil when no editor is mounted.
    @Published var inlineEdit: InlineEdit?
    /// The Text tool's current typography; the inspector's TEXT STYLE controls
    /// edit this, and it seeds a new text box. Edit flows overwrite it with the
    /// edited target's real typography so the inspector shows true values.
    @Published var textStyle = TextStyle()

    /// Applies `change` to `textStyle` and mirrors the result into the open
    /// inline edit (if any), so inspector control changes show live as you type.
    func mutateTextStyle(_ change: (inout TextStyle) -> Void) {
        change(&textStyle)
        if inlineEdit != nil {
            inlineEdit?.style = textStyle
        }
    }

    /// Records the inline editor's current box (page space) as it is resized by
    /// drag handles or grown to fit the font. `@Published inlineEdit` fires
    /// `objectWillChange`, so the overlay re-reads the rect on the next update.
    func setInlineRect(_ rect: CGRect) {
        inlineEdit?.pageRectOverride = rect
    }

    /// Insertion order of annotations created this session, used to sort
    /// session-created annotations newest-first above pre-existing ones.
    var sessionCreatedOrder: [ObjectIdentifier] = []

    /// Snapshot of the document taken on markup entry; Cancel restores from this
    /// to discard everything done during the session.
    var entrySnapshot: Data?

    init() {
        self.activeSwatchID = Pheno.swatches.first?.id ?? "yellow"
    }

    var activeSwatch: Pheno.Swatch {
        Pheno.swatches.first(where: { $0.id == activeSwatchID }) ?? Pheno.swatches[0]
    }

    func recordCreated(_ annotation: PDFAnnotation) {
        sessionCreatedOrder.append(ObjectIdentifier(annotation))
    }

    func refreshAnnotations(document: PDFDocument) {
        var entries: [AnnotationEntry] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations {
                if annotation.userName == "PDFStack.editCover" { continue }
                guard let entry = makeEntry(for: annotation, on: page, pageNumber: pageIndex + 1) else { continue }
                entries.append(entry)
            }
        }

        let order = sessionCreatedOrder
        let orderIndex: (ObjectIdentifier) -> Int? = { id in
            order.firstIndex(of: id)
        }
        annotations = entries.sorted { lhs, rhs in
            let l = orderIndex(lhs.id)
            let r = orderIndex(rhs.id)
            switch (l, r) {
            case let (l?, r?):
                return l > r // newest session-created first
            case (.some, .none):
                return true // session-created above pre-existing
            case (.none, .some):
                return false
            case (.none, .none):
                return false // keep document order
            }
        }
    }

    private func makeEntry(for annotation: PDFAnnotation, on page: PDFPage, pageNumber: Int) -> AnnotationEntry? {
        let title: String
        let indicatorColor: NSColor
        let isSquare: Bool

        switch annotation.type {
        case "Highlight":
            title = "Highlight"
            indicatorColor = annotation.color
            isSquare = false
        case "Underline":
            title = "Underline"
            indicatorColor = annotation.color
            isSquare = false
        case "StrikeOut":
            title = "Strikethrough"
            indicatorColor = annotation.color
            isSquare = false
        case "Text":
            title = "Note"
            indicatorColor = NSColor(hex: 0x3F91BC)
            isSquare = true
        case "FreeText":
            title = annotation.userName == "PDFStack.editText" ? "Edited text" : "Text"
            indicatorColor = NSColor(hex: 0x3F91BC)
            isSquare = true
        default:
            return nil
        }

        let subtitle: String
        if let contents = annotation.contents, !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            subtitle = contents
        } else if let selected = page.selection(for: annotation.bounds)?.string?
            .trimmingCharacters(in: .whitespacesAndNewlines), !selected.isEmpty {
            subtitle = selected
        } else {
            subtitle = "Page \(pageNumber)"
        }

        return AnnotationEntry(
            id: ObjectIdentifier(annotation),
            annotation: annotation,
            page: page,
            title: title,
            subtitle: subtitle,
            indicatorColor: indicatorColor,
            isSquareIndicator: isSquare
        )
    }
}
