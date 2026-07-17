import AppKit
import PDFKit

/// Full typography for text-creating operations, so the inline editor can commit
/// styled text.
public struct TextStyle {
    public var fontName: String?
    public var fontSize: CGFloat
    public var color: NSColor
    public var alignment: NSTextAlignment

    public init(fontName: String? = nil, fontSize: CGFloat = 14, color: NSColor = .black, alignment: NSTextAlignment = .left) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.color = color
        self.alignment = alignment
    }

    public var font: NSFont {
        fontName.flatMap { NSFont(name: $0, size: fontSize) } ?? NSFont.systemFont(ofSize: fontSize)
    }
}

public enum PDFAnnotationOperations {
    /// Adds one highlight annotation per line of `selection`, each bounded to that
    /// line only. A single annotation spanning a multi-line selection's overall
    /// bounding box would incorrectly cover the gaps between lines.
    @discardableResult
    public static func highlight(_ selection: PDFSelection, color: NSColor = .yellow, alpha: CGFloat = 1.0) -> [PDFAnnotation] {
        addTextMarkup(for: selection, subtype: .highlight, color: color.withAlphaComponent(alpha))
    }

    @discardableResult
    public static func underline(_ selection: PDFSelection, color: NSColor = .black, alpha: CGFloat = 1.0) -> [PDFAnnotation] {
        addTextMarkup(for: selection, subtype: .underline, color: color.withAlphaComponent(alpha))
    }

    @discardableResult
    public static func strikeThrough(_ selection: PDFSelection, color: NSColor = .red, alpha: CGFloat = 1.0) -> [PDFAnnotation] {
        addTextMarkup(for: selection, subtype: .strikeOut, color: color.withAlphaComponent(alpha))
    }

    private static func addTextMarkup(
        for selection: PDFSelection,
        subtype: PDFAnnotationSubtype,
        color: NSColor
    ) -> [PDFAnnotation] {
        var created: [PDFAnnotation] = []
        for lineSelection in selection.selectionsByLine() {
            guard let page = lineSelection.pages.first else { continue }
            let bounds = lineSelection.bounds(for: page)
            guard bounds.width > 0, bounds.height > 0 else { continue }
            let annotation = PDFAnnotation(bounds: bounds, forType: subtype, withProperties: nil)
            annotation.color = color
            page.addAnnotation(annotation)
            created.append(annotation)
        }
        return created
    }

    @discardableResult
    public static func addNote(on page: PDFPage, at point: CGPoint, text: String) -> PDFAnnotation {
        let bounds = CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20)
        let annotation = PDFAnnotation(bounds: bounds, forType: .text, withProperties: nil)
        annotation.contents = text
        annotation.iconType = .comment
        annotation.color = .systemYellow
        page.addAnnotation(annotation)
        return annotation
    }

    @discardableResult
    public static func addFreeText(
        on page: PDFPage,
        at point: CGPoint,
        text: String,
        style: TextStyle = TextStyle(),
        size: CGSize? = nil
    ) -> PDFAnnotation {
        let boxSize = size ?? CGSize(width: 220, height: 40)
        let bounds = CGRect(x: point.x, y: point.y - boxSize.height / 2, width: boxSize.width, height: boxSize.height)
        let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
        annotation.contents = text
        annotation.font = style.font
        annotation.fontColor = style.color
        annotation.alignment = style.alignment
        // New text should not mask the page: use a clear background rather than the
        // opaque white the tool previously used, so the annotation reads cleanly over
        // existing page content.
        annotation.color = .clear
        page.addAnnotation(annotation)
        return annotation
    }

    public static func remove(_ annotation: PDFAnnotation, from page: PDFPage) {
        page.removeAnnotation(annotation)
    }

    public static func setContents(_ contents: String, of annotation: PDFAnnotation) {
        annotation.contents = contents
    }

    public struct TextBlockReplacement {
        public let cover: PDFAnnotation
        public let text: PDFAnnotation
    }

    /// Visually replaces `block`'s text: an opaque square annotation covers the
    /// original glyphs (the content stream itself is immutable via PDFKit), and
    /// a FreeText annotation re-sets the new text in the block's detected
    /// typography at the same bounds. Both are ordinary annotations, so the
    /// existing Erase tool can undo the edit.
    @discardableResult
    public static func replaceTextBlock(
        _ block: TextBlock,
        on page: PDFPage,
        with newText: String,
        backgroundColor: NSColor = .white,
        style: TextStyle? = nil
    ) -> TextBlockReplacement {
        let coverBounds = block.bounds.insetBy(dx: -2, dy: -2)

        let cover = PDFAnnotation(bounds: coverBounds, forType: .square, withProperties: nil)
        cover.color = backgroundColor
        cover.interiorColor = backgroundColor
        cover.userName = "PDFStack.editCover"
        let border = PDFBorder()
        border.lineWidth = 0
        cover.border = border
        page.addAnnotation(cover)

        let text = PDFAnnotation(bounds: coverBounds, forType: .freeText, withProperties: nil)
        text.userName = "PDFStack.editText"
        text.contents = newText
        if let style = style {
            text.font = style.font
            text.fontColor = style.color
            text.alignment = style.alignment
        } else {
            text.font = block.fontName.flatMap { NSFont(name: $0, size: block.fontSize) }
                ?? NSFont.systemFont(ofSize: block.fontSize)
            text.fontColor = block.textColor ?? .black
            text.alignment = .natural
        }
        text.color = .clear
        page.addAnnotation(text)

        return TextBlockReplacement(cover: cover, text: text)
    }
}
