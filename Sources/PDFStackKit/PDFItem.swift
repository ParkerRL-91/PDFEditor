import Foundation
import PDFKit

public struct PDFItem: Identifiable {
    public let id: UUID
    public var sourceURL: URL
    public var document: PDFDocument
    public var displayName: String

    public var pageCount: Int { document.pageCount }

    public init(id: UUID = UUID(), sourceURL: URL, document: PDFDocument, displayName: String) {
        self.id = id
        self.sourceURL = sourceURL
        self.document = document
        self.displayName = displayName
    }
}
