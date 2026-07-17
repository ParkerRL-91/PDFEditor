import Combine
import Foundation
import PDFKit
// SwiftUI for Array.move(fromOffsets:toOffset:) — no Foundation/Combine equivalent exists
import SwiftUI

public enum ImportResult: Equatable {
    case added
    case duplicate
    case locked
    case restricted
    case unreadable
}

public final class AppState: ObservableObject {
    @Published public var items: [PDFItem] = []
    @Published public var selectedItemID: PDFItem.ID?
    @Published public var lastSaveDirectory: URL?
    /// Toggled by the app's Open… menu command; observed by the view that owns the import panel.
    @Published public var openFileMenuRequest: Int = 0
    /// Toggled by the app's Save… menu command; observed by the view that owns the save dialog.
    @Published public var saveMenuRequest: Int = 0
    /// URLs handed to the app via Finder (Open With / double-click / Dock drop), queued here by
    /// the app delegate and drained by the view that owns the shared import controller — keeps
    /// AppKit delegate wiring out of PDFStackKit while reusing the import/password flow.
    @Published public var pendingOpenURLs: [URL] = []

    public init() {}

    public var selectedItem: PDFItem? {
        items.first { $0.id == selectedItemID }
    }

    @discardableResult
    public func addPDF(at url: URL) -> ImportResult {
        guard !isAlreadyAdded(url) else { return .duplicate }
        guard let document = PDFDocument(url: url) else { return .unreadable }
        if document.isLocked { return .locked }
        // Reject PDFs whose owner-password permissions block assembly: PDFKit will
        // still open/copy/write their pages, but the written pages come back
        // content-stripped, silently discarding real data.
        guard document.allowsDocumentAssembly else { return .restricted }
        append(document: document, sourceURL: url)
        return .added
    }

    /// Unlocks a password-protected PDF and, on success, imports it exactly as `addPDF(at:)` would.
    @discardableResult
    public func addPDF(at url: URL, password: String) -> ImportResult {
        guard !isAlreadyAdded(url) else { return .duplicate }
        guard let document = PDFDocument(url: url) else { return .unreadable }
        guard document.unlock(withPassword: password) else { return .locked }
        guard document.allowsDocumentAssembly else { return .restricted }
        append(document: document, sourceURL: url)
        return .added
    }

    private func isAlreadyAdded(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        return items.contains { $0.sourceURL.standardizedFileURL == standardized }
    }

    private func append(document: PDFDocument, sourceURL: URL) {
        let item = PDFItem(
            sourceURL: sourceURL,
            document: document,
            displayName: sourceURL.deletingPathExtension().lastPathComponent
        )
        items.append(item)
        if selectedItemID == nil {
            selectedItemID = item.id
        }
    }

    public func removeItem(id: PDFItem.ID) {
        items.removeAll { $0.id == id }
        if selectedItemID == id {
            selectedItemID = items.first?.id
        }
    }

    public func moveItems(fromOffsets source: IndexSet, toOffset destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    public func replaceItem(id: PDFItem.ID, withDocuments documents: [PDFDocument]) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let original = items[index]
        let newItems = documents.enumerated().map { offset, document in
            PDFItem(
                sourceURL: original.sourceURL,
                document: document,
                displayName: "\(original.displayName) (part \(offset + 1))"
            )
        }
        items.replaceSubrange(index...index, with: newItems)
        if selectedItemID == id {
            selectedItemID = newItems.first?.id
        }
    }

    public func updateDocument(id: PDFItem.ID, document: PDFDocument) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].document = document
    }

    public func insertItem(after id: PDFItem.ID, document: PDFDocument, displayName: String) {
        guard let sourceIndex = items.firstIndex(where: { $0.id == id }) else { return }
        let source = items[sourceIndex]
        let newItem = PDFItem(sourceURL: source.sourceURL, document: document, displayName: displayName)
        items.insert(newItem, at: sourceIndex + 1)
    }

    /// Renames the item with the given id. Whitespace is trimmed; an empty result is rejected
    /// and the existing name is kept.
    public func renameItem(id: PDFItem.ID, to newName: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items[index].displayName = trimmed
    }

    /// Inserts a deep, independent copy of the item with the given id directly after it.
    public func duplicateItem(id: PDFItem.ID) {
        guard let sourceIndex = items.firstIndex(where: { $0.id == id }) else { return }
        let source = items[sourceIndex]
        let copy = PDFDocument()
        var destIndex = 0
        for index in 0..<source.document.pageCount {
            guard let page = source.document.page(at: index),
                  let pageCopy = page.copy() as? PDFPage else { continue }
            copy.insert(pageCopy, at: destIndex)
            destIndex += 1
        }
        let newItem = PDFItem(sourceURL: source.sourceURL, document: copy, displayName: "\(source.displayName) copy")
        items.insert(newItem, at: sourceIndex + 1)
    }
}
