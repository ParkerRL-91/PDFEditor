import AppKit
import PDFKit

/// A visually contiguous run of text lines on a page -- a paragraph, heading,
/// or list item -- with the typography needed to re-set it as an annotation.
public struct TextBlock: Equatable {
    /// Union of the member lines' bounds, in page space.
    public let bounds: CGRect
    /// Member lines' text joined with single spaces (reflowed, not layout-preserving).
    public let text: String
    public let fontName: String?
    public let fontSize: CGFloat
    public let textColor: NSColor?

    public init(bounds: CGRect, text: String, fontName: String?, fontSize: CGFloat, textColor: NSColor?) {
        self.bounds = bounds
        self.text = text
        self.fontName = fontName
        self.fontSize = fontSize
        self.textColor = textColor
    }
}

public enum PDFTextBlockDetector {
    /// Groups the page's text lines into blocks, top of page first.
    public static func blocks(on page: PDFPage) -> [TextBlock] {
        guard let fullSelection = page.selection(for: page.bounds(for: .mediaBox)) else { return [] }
        let lines: [(bounds: CGRect, selection: PDFSelection)] = fullSelection.selectionsByLine()
            .compactMap { line in
                let bounds = line.bounds(for: page)
                guard bounds.width > 0, bounds.height > 0,
                      let text = line.string,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return (bounds, line)
            }
        guard !lines.isEmpty else { return [] }

        // PDF page space is bottom-up, so "top of page first" means max Y first.
        let sorted = lines.sorted { $0.bounds.maxY > $1.bounds.maxY }

        var groups: [[(bounds: CGRect, selection: PDFSelection)]] = [[sorted[0]]]
        for line in sorted.dropFirst() {
            if let previous = groups[groups.count - 1].last,
               belongsToSameBlock(above: previous.bounds, below: line.bounds) {
                groups[groups.count - 1].append(line)
            } else {
                groups.append([line])
            }
        }
        return groups.map { makeBlock(from: $0) }
    }

    /// The block whose (slightly padded) bounds contain `point`, if any.
    public static func block(at point: CGPoint, on page: PDFPage) -> TextBlock? {
        blocks(on: page).first { $0.bounds.insetBy(dx: -2, dy: -2).contains(point) }
    }

    /// Adjacent lines are the same block when the vertical gap between them is
    /// smaller than ~80% of a line height (ordinary leading; paragraph breaks
    /// and section gaps are larger) and they overlap horizontally (side-by-side
    /// columns must not merge).
    private static func belongsToSameBlock(above: CGRect, below: CGRect) -> Bool {
        let gap = above.minY - below.maxY
        let lineHeight = max(above.height, below.height)
        guard gap < lineHeight * 0.8 else { return false }
        let horizontalOverlap = min(above.maxX, below.maxX) - max(above.minX, below.minX)
        return horizontalOverlap > 0
    }

    private static func makeBlock(from lines: [(bounds: CGRect, selection: PDFSelection)]) -> TextBlock {
        var bounds = lines[0].bounds
        for line in lines.dropFirst() {
            bounds = bounds.union(line.bounds)
        }
        let text = lines
            .compactMap { $0.selection.string?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: " ")

        var fontName: String?
        var fontSize: CGFloat = 12
        var textColor: NSColor?
        if let attributed = lines[0].selection.attributedString, attributed.length > 0 {
            let attributes = attributed.attributes(at: 0, effectiveRange: nil)
            if let font = attributes[.font] as? NSFont {
                fontName = font.fontName
                fontSize = font.pointSize
            }
            textColor = attributes[.foregroundColor] as? NSColor
        }
        return TextBlock(bounds: bounds, text: text, fontName: fontName, fontSize: fontSize, textColor: textColor)
    }
}
