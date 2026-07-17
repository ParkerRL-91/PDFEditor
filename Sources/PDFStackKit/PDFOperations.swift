import PDFKit

public enum PDFOperationError: Error, Equatable {
    case invalidRange
    case noMarkers
    case emptySelection
    case wouldDeleteAllPages
}

public enum PDFOperations {
    /// Returns a new document containing only the 1-based, inclusive page range from `source`.
    public static func trim(_ source: PDFDocument, keepingPages range: ClosedRange<Int>) throws -> PDFDocument {
        guard range.lowerBound >= 1, range.upperBound <= source.pageCount else {
            throw PDFOperationError.invalidRange
        }
        let result = PDFDocument()
        var destIndex = 0
        for pageNumber in range {
            guard let page = source.page(at: pageNumber - 1),
                  let pageCopy = page.copy() as? PDFPage else { continue }
            result.insert(pageCopy, at: destIndex)
            destIndex += 1
        }
        return result
    }

    /// Splits `source` into pieces using 1-based "split after this page" markers.
    /// e.g. pageCount 8, markers [3, 5] -> pieces covering 1...3, 4...5, 6...8.
    public static func split(_ source: PDFDocument, afterPages markers: [Int]) throws -> [PDFDocument] {
        guard !markers.isEmpty else { throw PDFOperationError.noMarkers }
        let sortedMarkers = Array(Set(markers)).sorted()
        guard sortedMarkers.allSatisfy({ $0 >= 1 && $0 < source.pageCount }) else {
            throw PDFOperationError.invalidRange
        }
        var boundaries = sortedMarkers
        boundaries.append(source.pageCount)

        var pieces: [PDFDocument] = []
        var start = 1
        for end in boundaries {
            let piece = PDFDocument()
            var destIndex = 0
            for pageNumber in start...end {
                guard let page = source.page(at: pageNumber - 1),
                      let pageCopy = page.copy() as? PDFPage else { continue }
                piece.insert(pageCopy, at: destIndex)
                destIndex += 1
            }
            pieces.append(piece)
            start = end + 1
        }
        return pieces
    }

    /// Merges documents in argument order into one new document.
    public static func merge(_ documents: [PDFDocument]) -> PDFDocument {
        let result = PDFDocument()
        var destIndex = 0
        for document in documents {
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index),
                      let pageCopy = page.copy() as? PDFPage else { continue }
                result.insert(pageCopy, at: destIndex)
                destIndex += 1
            }
        }
        return result
    }

    /// Returns a new document identical to `source`, with the 1-based `pages`
    /// rotated clockwise by `degrees` (positive) or counter-clockwise (negative).
    public static func rotate(_ source: PDFDocument, pages: Set<Int>, by degrees: Int) throws -> PDFDocument {
        guard !pages.isEmpty else { throw PDFOperationError.emptySelection }
        guard pages.allSatisfy({ $0 >= 1 && $0 <= source.pageCount }) else {
            throw PDFOperationError.invalidRange
        }
        let result = PDFDocument()
        var destIndex = 0
        for pageNumber in 1...source.pageCount {
            guard let page = source.page(at: pageNumber - 1),
                  let pageCopy = page.copy() as? PDFPage else { continue }
            if pages.contains(pageNumber) {
                pageCopy.rotation = (pageCopy.rotation + degrees) % 360
            }
            result.insert(pageCopy, at: destIndex)
            destIndex += 1
        }
        return result
    }

    /// Returns a new document containing every page of `source` NOT in the 1-based `pages` set.
    public static func delete(_ source: PDFDocument, pages: Set<Int>) throws -> PDFDocument {
        guard !pages.isEmpty else { throw PDFOperationError.emptySelection }
        guard pages.allSatisfy({ $0 >= 1 && $0 <= source.pageCount }) else {
            throw PDFOperationError.invalidRange
        }
        guard pages.count < source.pageCount else {
            throw PDFOperationError.wouldDeleteAllPages
        }
        let result = PDFDocument()
        var destIndex = 0
        for pageNumber in 1...source.pageCount where !pages.contains(pageNumber) {
            guard let page = source.page(at: pageNumber - 1),
                  let pageCopy = page.copy() as? PDFPage else { continue }
            result.insert(pageCopy, at: destIndex)
            destIndex += 1
        }
        return result
    }

    /// Returns a new document built from the 1-based `pageNumbers` of `source`,
    /// in the order given. Out-of-range page numbers are skipped.
    public static func extractPages(_ source: PDFDocument, pageNumbers: [Int]) -> PDFDocument {
        let result = PDFDocument()
        var destIndex = 0
        for pageNumber in pageNumbers {
            guard pageNumber >= 1, pageNumber <= source.pageCount,
                  let page = source.page(at: pageNumber - 1),
                  let pageCopy = page.copy() as? PDFPage else { continue }
            result.insert(pageCopy, at: destIndex)
            destIndex += 1
        }
        return result
    }

    /// Returns a new document containing exactly the 1-based `pages`, in ascending order.
    public static func extract(_ source: PDFDocument, pages: Set<Int>) throws -> PDFDocument {
        guard !pages.isEmpty else { throw PDFOperationError.emptySelection }
        guard pages.allSatisfy({ $0 >= 1 && $0 <= source.pageCount }) else {
            throw PDFOperationError.invalidRange
        }
        let result = PDFDocument()
        var destIndex = 0
        for pageNumber in pages.sorted() {
            guard let page = source.page(at: pageNumber - 1),
                  let pageCopy = page.copy() as? PDFPage else { continue }
            result.insert(pageCopy, at: destIndex)
            destIndex += 1
        }
        return result
    }
}
