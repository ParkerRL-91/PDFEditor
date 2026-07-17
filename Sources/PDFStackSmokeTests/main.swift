import AppKit
import Foundation
import PDFKit
import PDFStackKit

/// Builds an in-memory PDF where each page contains the given visible text,
/// so operations on it can be verified by reading the text back out.
func makeDocument(pageTexts: [String]) -> PDFDocument {
    let pageRect = CGRect(x: 0, y: 0, width: 200, height: 200)
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
        fatalError("Could not create PDF data consumer")
    }
    var mediaBox = pageRect
    guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        fatalError("Could not create PDF context")
    }
    for text in pageTexts {
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 24)]
        (text as NSString).draw(at: CGPoint(x: 20, y: 90), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
    }
    context.closePDF()
    guard let document = PDFDocument(data: data as Data) else {
        fatalError("Could not load generated PDF")
    }
    return document
}

func pageTexts(of document: PDFDocument) -> [String] {
    (0..<document.pageCount).compactMap {
        document.page(at: $0)?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

var failures: [String] = []
func check(_ condition: Bool, _ message: String) {
    if !condition { failures.append(message) }
}

let doc8 = makeDocument(pageTexts: (1...8).map { "Page \($0)" })

// trim: keeps the requested range
do {
    let trimmed = try PDFOperations.trim(doc8, keepingPages: 3...5)
    check(trimmed.pageCount == 3, "trim: expected 3 pages, got \(trimmed.pageCount)")
    check(pageTexts(of: trimmed) == ["Page 3", "Page 4", "Page 5"],
          "trim: expected [Page 3, Page 4, Page 5], got \(pageTexts(of: trimmed))")
} catch {
    failures.append("trim: threw unexpected error \(error)")
}

// trim: rejects an out-of-bounds range
do {
    _ = try PDFOperations.trim(doc8, keepingPages: 6...10)
    failures.append("trim: expected invalidRange error for out-of-bounds range, got none")
} catch PDFOperationError.invalidRange {
    // expected
} catch {
    failures.append("trim: expected invalidRange, got \(error)")
}

// split: divides at markers, in order
do {
    let pieces = try PDFOperations.split(doc8, afterPages: [3, 5])
    check(pieces.count == 3, "split: expected 3 pieces, got \(pieces.count)")
    check(pieces.map { $0.pageCount } == [3, 2, 3],
          "split: expected page counts [3, 2, 3], got \(pieces.map { $0.pageCount })")
    check(pageTexts(of: pieces[0]) == ["Page 1", "Page 2", "Page 3"],
          "split: first piece expected [Page 1, Page 2, Page 3], got \(pageTexts(of: pieces[0]))")
    check(pageTexts(of: pieces[2]) == ["Page 6", "Page 7", "Page 8"],
          "split: third piece expected [Page 6, Page 7, Page 8], got \(pageTexts(of: pieces[2]))")
} catch {
    failures.append("split: threw unexpected error \(error)")
}

// split: rejects an empty marker list
do {
    _ = try PDFOperations.split(doc8, afterPages: [])
    failures.append("split: expected noMarkers error for empty markers, got none")
} catch PDFOperationError.noMarkers {
    // expected
} catch {
    failures.append("split: expected noMarkers, got \(error)")
}

// merge: concatenates in argument order
let docA = makeDocument(pageTexts: ["A1", "A2"])
let docB = makeDocument(pageTexts: ["B1"])
let merged = PDFOperations.merge([docA, docB])
check(merged.pageCount == 3, "merge: expected 3 pages, got \(merged.pageCount)")
check(pageTexts(of: merged) == ["A1", "A2", "B1"],
      "merge: expected [A1, A2, B1], got \(pageTexts(of: merged))")

// AppState: add, auto-select, reject invalid files
let state = AppState()
let tempX = URL(fileURLWithPath: "/tmp/pdfstack-smoketest-x.pdf")
let tempY = URL(fileURLWithPath: "/tmp/pdfstack-smoketest-y.pdf")
try? makeDocument(pageTexts: ["X1", "X2"]).dataRepresentation()?.write(to: tempX)
try? makeDocument(pageTexts: ["Y1"]).dataRepresentation()?.write(to: tempY)
defer {
    try? FileManager.default.removeItem(at: tempX)
    try? FileManager.default.removeItem(at: tempY)
}

check(state.addPDF(at: tempX) == .added, "AppState.addPDF: expected .added for a valid PDF")
check(state.items.count == 1, "AppState: expected 1 item after first addPDF, got \(state.items.count)")
check(state.selectedItemID == state.items.first?.id, "AppState: expected the first item to be auto-selected")

let badURL = URL(fileURLWithPath: "/tmp/pdfstack-smoketest-missing-\(UUID().uuidString).pdf")
check(state.addPDF(at: badURL) == .unreadable, "AppState.addPDF: expected .unreadable for a nonexistent file")
check(state.items.count == 1, "AppState: expected item count unchanged after a failed add, got \(state.items.count)")

check(state.addPDF(at: tempY) == .added, "AppState.addPDF: expected .added for a second valid PDF")
check(state.items.count == 2, "AppState: expected 2 items, got \(state.items.count)")

check(state.addPDF(at: tempX) == .duplicate, "AppState.addPDF: expected .duplicate for re-adding an already-listed file")
check(state.items.count == 2, "AppState: expected item count unchanged after a duplicate add, got \(state.items.count)")

// moveItems: reorder
state.moveItems(fromOffsets: IndexSet(integer: 1), toOffset: 0)
check(state.items[0].sourceURL == tempY, "AppState.moveItems: expected the second item moved to the front")

// replaceItem: split one item into two, in place
let itemToSplit = state.items[1] // the X document (2 pages)
let splitPieces = try PDFOperations.split(itemToSplit.document, afterPages: [1])
state.replaceItem(id: itemToSplit.id, withDocuments: splitPieces)
check(state.items.count == 3, "AppState.replaceItem: expected 3 items total, got \(state.items.count)")
check(state.items[1].pageCount == 1 && state.items[2].pageCount == 1,
      "AppState.replaceItem: expected both replacement items to have 1 page each")

// removeItem
let idToRemove = state.items[0].id
state.removeItem(id: idToRemove)
check(state.items.count == 2, "AppState.removeItem: expected 2 items remaining, got \(state.items.count)")
check(!state.items.contains { $0.id == idToRemove }, "AppState.removeItem: removed item should no longer be present")

// updateDocument
let idToUpdate = state.items[0].id
state.updateDocument(id: idToUpdate, document: makeDocument(pageTexts: ["Z1", "Z2", "Z3"]))
check(state.items[0].pageCount == 3, "AppState.updateDocument: expected 3 pages, got \(state.items[0].pageCount)")

// PDFAnnotationOperations: highlight spans exactly the selected lines
let annotDoc = makeDocument(pageTexts: ["Alpha Beta Gamma", "Delta Epsilon"])
guard let annotPage = annotDoc.page(at: 0) else {
    fatalError("annotations: expected page 0 to exist")
}
if let fullPageSelection = annotPage.selection(for: annotPage.bounds(for: .mediaBox)) {
    let created = PDFAnnotationOperations.highlight(fullPageSelection, color: .yellow)
    check(!created.isEmpty, "highlight: expected at least one annotation, got 0")
    check(annotPage.annotations.count == created.count,
          "highlight: expected page.annotations to contain exactly the created annotations, got \(annotPage.annotations.count) vs \(created.count)")
    for annotation in created {
        check(annotation.type == "Highlight", "highlight: expected annotation type Highlight, got \(annotation.type ?? "nil")")
    }
}

// underline / strikeOut use the same mechanism with different subtypes
let markupDoc = makeDocument(pageTexts: ["Underline Me"])
if let markupPage = markupDoc.page(at: 0),
   let sel = markupPage.selection(for: markupPage.bounds(for: .mediaBox)) {
    let underlines = PDFAnnotationOperations.underline(sel, color: .black)
    check(!underlines.isEmpty && underlines.allSatisfy { $0.type == "Underline" },
          "underline: expected non-empty Underline annotations, got \(underlines.map { $0.type ?? "nil" })")

    let strikes = PDFAnnotationOperations.strikeThrough(sel, color: .red)
    check(!strikes.isEmpty && strikes.allSatisfy { $0.type == "StrikeOut" },
          "strikeThrough: expected non-empty StrikeOut annotations, got \(strikes.map { $0.type ?? "nil" })")
}

// addNote / addFreeText / remove
let noteDoc = makeDocument(pageTexts: ["Note page"])
if let notePage = noteDoc.page(at: 0) {
    let note = PDFAnnotationOperations.addNote(on: notePage, at: CGPoint(x: 50, y: 50), text: "A comment")
    check(notePage.annotations.contains(note), "addNote: expected the page to contain the created note annotation")
    check(note.contents == "A comment", "addNote: expected contents 'A comment', got \(note.contents ?? "nil")")

    let freeText = PDFAnnotationOperations.addFreeText(on: notePage, at: CGPoint(x: 20, y: 100), text: "Some text")
    check(notePage.annotations.contains(freeText), "addFreeText: expected the page to contain the created free text annotation")
    check(freeText.contents == "Some text", "addFreeText: expected contents 'Some text', got \(freeText.contents ?? "nil")")

    let countBeforeRemove = notePage.annotations.count
    PDFAnnotationOperations.remove(note, from: notePage)
    // Note: a `.text`-subtype annotation causes PDFKit to auto-synthesize a linked
    // `Popup` annotation that also lives in page.annotations, so removing the note
    // drops the count by 2, not 1 (removeAnnotation correctly cascades the Popup too —
    // this is just PDFKit's own bookkeeping, not something PDFAnnotationOperations controls).
    // Assert the count strictly decreased and the note itself is gone, rather than an
    // exact -1 delta, so this doesn't depend on how many sibling annotations PDFKit adds.
    check(notePage.annotations.count < countBeforeRemove,
          "remove: expected annotation count to decrease, went from \(countBeforeRemove) to \(notePage.annotations.count)")
    check(!notePage.annotations.contains(note), "remove: expected the removed annotation to no longer be present")
}

// Annotations survive PDFOperations.trim (PDFPage.copy() must preserve them)
let trimAnnotDoc = makeDocument(pageTexts: ["Page A", "Page B", "Page C"])
if let pageB = trimAnnotDoc.page(at: 1), let selB = pageB.selection(for: pageB.bounds(for: .mediaBox)) {
    PDFAnnotationOperations.highlight(selB, color: .yellow)
    do {
        let trimmed = try PDFOperations.trim(trimAnnotDoc, keepingPages: 2...2)
        check(trimmed.pageCount == 1, "trim+annotations: expected 1 page, got \(trimmed.pageCount)")
        let trimmedAnnotationCount = trimmed.page(at: 0)?.annotations.count ?? 0
        check(trimmedAnnotationCount > 0,
              "trim+annotations: expected the trimmed page's annotations to survive the copy, got \(trimmedAnnotationCount)")
    } catch {
        failures.append("trim+annotations: threw unexpected error \(error)")
    }
}

// Annotations survive PDFOperations.split
let splitAnnotDoc = makeDocument(pageTexts: ["One", "Two"])
if let splitPage = splitAnnotDoc.page(at: 0), let splitSel = splitPage.selection(for: splitPage.bounds(for: .mediaBox)) {
    PDFAnnotationOperations.highlight(splitSel, color: .yellow)
    do {
        let pieces = try PDFOperations.split(splitAnnotDoc, afterPages: [1])
        let firstPieceAnnotationCount = pieces.first?.page(at: 0)?.annotations.count ?? 0
        check(firstPieceAnnotationCount > 0,
              "split+annotations: expected the first piece's page to retain its annotation, got \(firstPieceAnnotationCount)")
    } catch {
        failures.append("split+annotations: threw unexpected error \(error)")
    }
}

// Annotations survive PDFOperations.merge
let mergeAnnotDocA = makeDocument(pageTexts: ["Merge A"])
let mergeAnnotDocB = makeDocument(pageTexts: ["Merge B"])
if let mergePageA = mergeAnnotDocA.page(at: 0), let mergeSelA = mergePageA.selection(for: mergePageA.bounds(for: .mediaBox)) {
    PDFAnnotationOperations.highlight(mergeSelA, color: .yellow)
    let merged = PDFOperations.merge([mergeAnnotDocA, mergeAnnotDocB])
    let mergedAnnotationCount = merged.page(at: 0)?.annotations.count ?? 0
    check(mergedAnnotationCount > 0,
          "merge+annotations: expected the first merged page's annotations to survive the copy, got \(mergedAnnotationCount)")
}

// Annotations survive a write-to-disk-and-reread round trip
let writeAnnotDoc = makeDocument(pageTexts: ["Persisted"])
let writeAnnotURL = URL(fileURLWithPath: "/tmp/pdfstack-smoketest-annotations.pdf")
if let writePage = writeAnnotDoc.page(at: 0), let writeSel = writePage.selection(for: writePage.bounds(for: .mediaBox)) {
    PDFAnnotationOperations.highlight(writeSel, color: .yellow)
    let wroteOK = writeAnnotDoc.write(to: writeAnnotURL)
    check(wroteOK, "annotations round trip: expected write(to:) to succeed")
    if let reread = PDFDocument(url: writeAnnotURL) {
        let rereadAnnotationCount = reread.page(at: 0)?.annotations.count ?? 0
        check(rereadAnnotationCount > 0,
              "annotations round trip: expected re-read document to have >0 annotations, got \(rereadAnnotationCount)")
    } else {
        failures.append("annotations round trip: expected to re-read the written PDF, got nil")
    }
    try? FileManager.default.removeItem(at: writeAnnotURL)
}

// Highlight annotations must be VISIBLE when the page is drawn, not just present
// in page.annotations — a regression here would mean markup silently produces
// invisible output. Renders the page to a bitmap and counts distinctly-yellow
// pixels before and after highlighting.
func yellowishPixelCount(_ page: PDFPage) -> Int {
    let bounds = page.bounds(for: .mediaBox)
    let width = Int(bounds.width)
    let height = Int(bounds.height)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return -1 }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    page.draw(with: .mediaBox, to: ctx.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    var count = 0
    for y in 0..<height {
        for x in 0..<width {
            guard let c = rep.colorAt(x: x, y: y) else { continue }
            if c.redComponent > 0.7 && c.greenComponent > 0.7 && c.blueComponent < 0.5 { count += 1 }
        }
    }
    return count
}

let renderDoc = makeDocument(pageTexts: ["Visible Highlight Check"])
if let renderPage = renderDoc.page(at: 0), let renderSel = renderPage.selection(for: renderPage.bounds(for: .mediaBox)) {
    let before = yellowishPixelCount(renderPage)
    check(before == 0, "render visibility: expected 0 yellow pixels before highlighting, got \(before)")
    PDFAnnotationOperations.highlight(renderSel, color: .yellow)
    let after = yellowishPixelCount(renderPage)
    check(after > 100, "render visibility: expected >100 yellow pixels after highlighting, got \(after)")
}

// setContents: updates an existing note annotation's text, readable back afterward
let editNoteDoc = makeDocument(pageTexts: ["Editable note page"])
if let editNotePage = editNoteDoc.page(at: 0) {
    let editableNote = PDFAnnotationOperations.addNote(on: editNotePage, at: CGPoint(x: 50, y: 50), text: "Original text")
    check(editableNote.contents == "Original text", "setContents: expected initial contents 'Original text', got \(editableNote.contents ?? "nil")")
    PDFAnnotationOperations.setContents("Updated text", of: editableNote)
    check(editableNote.contents == "Updated text", "setContents: expected updated contents 'Updated text', got \(editableNote.contents ?? "nil")")
}

// rotate: rotates exactly the selected pages, leaves page count and annotations intact
let rotateDoc = makeDocument(pageTexts: ["R1", "R2", "R3"])
if let rotatePage2 = rotateDoc.page(at: 1), let rotateSel2 = rotatePage2.selection(for: rotatePage2.bounds(for: .mediaBox)) {
    PDFAnnotationOperations.highlight(rotateSel2, color: .yellow)
    do {
        let rotated = try PDFOperations.rotate(rotateDoc, pages: [2], by: 90)
        check(rotated.pageCount == 3, "rotate: expected page count unchanged at 3, got \(rotated.pageCount)")
        check(rotated.page(at: 0)?.rotation == 0, "rotate: expected page 1 rotation 0, got \(rotated.page(at: 0)?.rotation ?? -1)")
        check(rotated.page(at: 1)?.rotation == 90, "rotate: expected page 2 rotation 90, got \(rotated.page(at: 1)?.rotation ?? -1)")
        check(rotated.page(at: 2)?.rotation == 0, "rotate: expected page 3 rotation 0, got \(rotated.page(at: 2)?.rotation ?? -1)")
        check((rotated.page(at: 1)?.annotations.count ?? 0) > 0,
              "rotate: expected rotated page's annotations to survive the copy")

        // repeated rotation wraps correctly
        let rotatedAgain = try PDFOperations.rotate(rotated, pages: [2], by: 90)
        check(rotatedAgain.page(at: 1)?.rotation == 180, "rotate: expected page 2 rotation 180 after second +90, got \(rotatedAgain.page(at: 1)?.rotation ?? -1)")
        let rotatedToWrap = try PDFOperations.rotate(rotatedAgain, pages: [2], by: -270)
        check(rotatedToWrap.page(at: 1)?.rotation == -90 || rotatedToWrap.page(at: 1)?.rotation == 270,
              "rotate: expected wrapped rotation of -90 or 270, got \(rotatedToWrap.page(at: 1)?.rotation ?? -1)")
    } catch {
        failures.append("rotate: threw unexpected error \(error)")
    }
}

// rotate: rejects an empty selection
do {
    _ = try PDFOperations.rotate(rotateDoc, pages: [], by: 90)
    failures.append("rotate: expected emptySelection error for empty set, got none")
} catch PDFOperationError.emptySelection {
    // expected
} catch {
    failures.append("rotate: expected emptySelection, got \(error)")
}

// delete: removes exactly the selected pages, by text
let deleteDoc = makeDocument(pageTexts: ["D1", "D2", "D3", "D4"])
do {
    let afterDelete = try PDFOperations.delete(deleteDoc, pages: [2, 3])
    check(afterDelete.pageCount == 2, "delete: expected 2 remaining pages, got \(afterDelete.pageCount)")
    check(pageTexts(of: afterDelete) == ["D1", "D4"],
          "delete: expected [D1, D4] remaining, got \(pageTexts(of: afterDelete))")
} catch {
    failures.append("delete: threw unexpected error \(error)")
}

// delete: blocks deleting every page
do {
    _ = try PDFOperations.delete(deleteDoc, pages: [1, 2, 3, 4])
    failures.append("delete: expected wouldDeleteAllPages error when deleting all pages, got none")
} catch PDFOperationError.wouldDeleteAllPages {
    // expected
} catch {
    failures.append("delete: expected wouldDeleteAllPages, got \(error)")
}

// extract: creates a document with exactly the selected pages in ascending order, source untouched
let extractDoc = makeDocument(pageTexts: ["E1", "E2", "E3", "E4"])
do {
    let extracted = try PDFOperations.extract(extractDoc, pages: [4, 2])
    check(extracted.pageCount == 2, "extract: expected 2 extracted pages, got \(extracted.pageCount)")
    check(pageTexts(of: extracted) == ["E2", "E4"],
          "extract: expected [E2, E4] in ascending order, got \(pageTexts(of: extracted))")
    check(extractDoc.pageCount == 4, "extract: expected source document untouched at 4 pages, got \(extractDoc.pageCount)")
    check(pageTexts(of: extractDoc) == ["E1", "E2", "E3", "E4"],
          "extract: expected source pages unchanged, got \(pageTexts(of: extractDoc))")
} catch {
    failures.append("extract: threw unexpected error \(error)")
}

// AppState.insertItem: extract's sidebar insertion lands directly after the source
let pagesState = AppState()
let pagesTempSource = URL(fileURLWithPath: "/tmp/pdfstack-smoketest-pages-source.pdf")
try? makeDocument(pageTexts: ["S1", "S2"]).dataRepresentation()?.write(to: pagesTempSource)
defer { try? FileManager.default.removeItem(at: pagesTempSource) }
pagesState.addPDF(at: pagesTempSource)
let pagesSourceItem = pagesState.items[0]
let pagesTrailingURL = URL(fileURLWithPath: "/tmp/pdfstack-smoketest-pages-trailing.pdf")
try? makeDocument(pageTexts: ["T1"]).dataRepresentation()?.write(to: pagesTrailingURL)
defer { try? FileManager.default.removeItem(at: pagesTrailingURL) }
pagesState.addPDF(at: pagesTrailingURL)
pagesState.insertItem(after: pagesSourceItem.id, document: makeDocument(pageTexts: ["S2"]), displayName: "\(pagesSourceItem.displayName) (extract)")
check(pagesState.items.count == 3, "AppState.insertItem: expected 3 items total, got \(pagesState.items.count)")
check(pagesState.items[1].displayName == "\(pagesSourceItem.displayName) (extract)",
      "AppState.insertItem: expected the extracted item directly after the source, got \(pagesState.items[1].displayName)")
check(pagesState.items[2].sourceURL == pagesTrailingURL,
      "AppState.insertItem: expected the original trailing item to remain after the inserted item")

// ImportResult: locked PDF is reported as .locked, and unlocks with the correct password
let lockedDoc = makeDocument(pageTexts: ["Secret page"])
let lockedURL = URL(fileURLWithPath: "/tmp/pdfstack-smoketest-locked.pdf")
defer { try? FileManager.default.removeItem(at: lockedURL) }
let lockedWriteOK = lockedDoc.write(
    to: lockedURL,
    withOptions: [.userPasswordOption: "correcthorse", .ownerPasswordOption: "correcthorse"]
)
check(lockedWriteOK, "ImportResult: expected the password-protected fixture to write successfully")

let importState = AppState()
check(importState.addPDF(at: lockedURL) == .locked, "AppState.addPDF: expected .locked for a password-protected PDF")
check(importState.items.isEmpty, "AppState.addPDF: expected no item added for a locked PDF before unlocking")

check(importState.addPDF(at: lockedURL, password: "wrongpassword") == .locked,
      "AppState.addPDF(password:): expected .locked for an incorrect password")
check(importState.items.isEmpty, "AppState.addPDF(password:): expected no item added after a wrong password")

check(importState.addPDF(at: lockedURL, password: "correcthorse") == .added,
      "AppState.addPDF(password:): expected .added for the correct password")
check(importState.items.count == 1, "AppState.addPDF(password:): expected 1 item after a correct-password unlock, got \(importState.items.count)")

// renameItem: trims and applies a valid name, rejects an empty (or whitespace-only) name
let renameState = AppState()
let renameTempURL = URL(fileURLWithPath: "/tmp/pdfstack-smoketest-rename.pdf")
try? makeDocument(pageTexts: ["Rename me"]).dataRepresentation()?.write(to: renameTempURL)
defer { try? FileManager.default.removeItem(at: renameTempURL) }
renameState.addPDF(at: renameTempURL)
let renameItemID = renameState.items[0].id
renameState.renameItem(id: renameItemID, to: "  Q3 Report  ")
check(renameState.items[0].displayName == "Q3 Report",
      "renameItem: expected trimmed name 'Q3 Report', got '\(renameState.items[0].displayName)'")
renameState.renameItem(id: renameItemID, to: "   ")
check(renameState.items[0].displayName == "Q3 Report",
      "renameItem: expected empty/whitespace name to be rejected, name changed to '\(renameState.items[0].displayName)'")
renameState.renameItem(id: renameItemID, to: "")
check(renameState.items[0].displayName == "Q3 Report",
      "renameItem: expected empty name to be rejected, name changed to '\(renameState.items[0].displayName)'")

// duplicateItem: inserts an independent deep copy directly after the source
let duplicateState = AppState()
let duplicateTempURL = URL(fileURLWithPath: "/tmp/pdfstack-smoketest-duplicate.pdf")
try? makeDocument(pageTexts: ["Dup1", "Dup2"]).dataRepresentation()?.write(to: duplicateTempURL)
defer { try? FileManager.default.removeItem(at: duplicateTempURL) }
duplicateState.addPDF(at: duplicateTempURL)
let duplicateTrailingURL = URL(fileURLWithPath: "/tmp/pdfstack-smoketest-duplicate-trailing.pdf")
try? makeDocument(pageTexts: ["Trail1"]).dataRepresentation()?.write(to: duplicateTrailingURL)
defer { try? FileManager.default.removeItem(at: duplicateTrailingURL) }
duplicateState.addPDF(at: duplicateTrailingURL)
let duplicateSourceItem = duplicateState.items[0]
duplicateState.duplicateItem(id: duplicateSourceItem.id)
check(duplicateState.items.count == 3, "duplicateItem: expected 3 items total, got \(duplicateState.items.count)")
check(duplicateState.items[1].displayName == "\(duplicateSourceItem.displayName) copy",
      "duplicateItem: expected the duplicate directly after the source named '\(duplicateSourceItem.displayName) copy', got '\(duplicateState.items[1].displayName)'")
check(duplicateState.items[1].pageCount == 2,
      "duplicateItem: expected the duplicate to have 2 pages, got \(duplicateState.items[1].pageCount)")
check(duplicateState.items[2].sourceURL == duplicateTrailingURL,
      "duplicateItem: expected the original trailing item to remain after the inserted duplicate")
if let duplicatedPage = duplicateState.items[1].document.page(at: 0),
   let duplicatedSelection = duplicatedPage.selection(for: duplicatedPage.bounds(for: .mediaBox)) {
    PDFAnnotationOperations.highlight(duplicatedSelection, color: .yellow)
}
check((duplicateState.items[1].document.page(at: 0)?.annotations.count ?? 0) > 0,
      "duplicateItem: expected mutating the duplicate's document to be possible")
check((duplicateState.items[0].document.page(at: 0)?.annotations.count ?? 0) == 0,
      "duplicateItem: expected mutating the duplicate to leave the original untouched")

// --- Text block detection ---

/// Two-line paragraph near the top (18pt baseline spacing at 14pt font ->
/// same block), plus one line far below (separate block).
func makeTextBlockDocument() -> PDFDocument {
    let pageRect = CGRect(x: 0, y: 0, width: 300, height: 300)
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
          var mediaBox = Optional(pageRect),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        fatalError("Could not create PDF context")
    }
    context.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14)]
    ("First line one" as NSString).draw(at: CGPoint(x: 20, y: 250), withAttributes: attributes)
    ("First line two" as NSString).draw(at: CGPoint(x: 20, y: 232), withAttributes: attributes)
    ("Second block" as NSString).draw(at: CGPoint(x: 20, y: 100), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()
    guard let document = PDFDocument(data: data as Data) else {
        fatalError("Could not load generated PDF")
    }
    return document
}

do {
    let doc = makeTextBlockDocument()
    guard let page = doc.page(at: 0) else { fatalError("blockdetect: no page") }
    let blocks = PDFTextBlockDetector.blocks(on: page)
    check(blocks.count == 2, "blockdetect: expected 2 blocks, got \(blocks.count)")
    if blocks.count == 2 {
        check(blocks[0].text == "First line one First line two",
              "blockdetect: block 0 text was '\(blocks[0].text)'")
        check(blocks[1].text == "Second block",
              "blockdetect: block 1 text was '\(blocks[1].text)'")
        check(blocks[0].bounds.minY > blocks[1].bounds.maxY,
              "blockdetect: block 0 should sit above block 1")
        check(abs(blocks[0].fontSize - 14) <= 2,
              "blockdetect: expected ~14pt font, got \(blocks[0].fontSize)")
        let hitPoint = CGPoint(x: blocks[0].bounds.midX, y: blocks[0].bounds.midY)
        check(PDFTextBlockDetector.block(at: hitPoint, on: page)?.text == blocks[0].text,
              "blockdetect: hit test at block 0 center missed")
        check(PDFTextBlockDetector.block(at: CGPoint(x: 280, y: 20), on: page) == nil,
              "blockdetect: hit test on empty region should be nil")
    }
}

// --- Text block replacement ---

/// Renders the page (annotations included) onto white and counts pixels darker
/// than 50% gray inside `region` (page space). Mirrors yellowishPixelCount.
func darkPixelCount(_ page: PDFPage, in region: CGRect) -> Int {
    let bounds = page.bounds(for: .mediaBox)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(bounds.width), pixelsHigh: Int(bounds.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let graphics = NSGraphicsContext(bitmapImageRep: rep) else { return 0 }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.cgContext.setFillColor(CGColor.white)
    graphics.cgContext.fill(bounds)
    page.draw(with: .mediaBox, to: graphics.cgContext)
    NSGraphicsContext.restoreGraphicsState()

    var count = 0
    let clamped = region.intersection(bounds)
    for x in Int(clamped.minX)..<Int(clamped.maxX) {
        for y in Int(clamped.minY)..<Int(clamped.maxY) {
            // Bitmap rows are top-down; page space is bottom-up.
            let bitmapY = Int(bounds.height) - 1 - y
            guard let color = rep.colorAt(x: x, y: bitmapY) else { continue }
            if color.redComponent < 0.5, color.greenComponent < 0.5, color.blueComponent < 0.5 {
                count += 1
            }
        }
    }
    return count
}

do {
    let doc = makeTextBlockDocument()
    guard let page = doc.page(at: 0) else { fatalError("blockreplace: no page") }
    let blocks = PDFTextBlockDetector.blocks(on: page)
    guard blocks.count == 2 else { fatalError("blockreplace: expected 2 blocks to start") }
    let target = blocks[0]

    let before = darkPixelCount(page, in: target.bounds)
    check(before > 50, "blockreplace: expected visible text before replacement, got \(before) dark px")

    let annotationCountBefore = page.annotations.count
    let replacement = PDFAnnotationOperations.replaceTextBlock(target, on: page, with: "")
    check(page.annotations.count == annotationCountBefore + 2,
          "blockreplace: expected 2 new annotations, got \(page.annotations.count - annotationCountBefore)")
    check(replacement.cover.type == "Square", "blockreplace: cover type was \(replacement.cover.type ?? "nil")")
    check(replacement.text.type == "FreeText", "blockreplace: text type was \(replacement.text.type ?? "nil")")
    check(replacement.text.contents == "", "blockreplace: contents was \(replacement.text.contents ?? "nil")")
    check(replacement.cover.bounds.contains(target.bounds),
          "blockreplace: cover \(replacement.cover.bounds) does not contain block \(target.bounds)")

    let after = darkPixelCount(page, in: target.bounds)
    check(after * 20 < before,
          "blockreplace: expected <5% residual dark pixels, before=\(before) after=\(after)")

    // Replacement with real text uses the detected typography.
    let second = PDFAnnotationOperations.replaceTextBlock(blocks[1], on: page, with: "Edited text")
    check(second.text.contents == "Edited text", "blockreplace: new text not stored")
    check(abs((second.text.font?.pointSize ?? 0) - blocks[1].fontSize) <= 2,
          "blockreplace: font size \(second.text.font?.pointSize ?? 0) vs detected \(blocks[1].fontSize)")
}

// highlight with alpha: the session opacity is baked into the annotation color
do {
    let alphaDoc = makeDocument(pageTexts: ["Alpha line for opacity"])
    if let alphaPage = alphaDoc.page(at: 0),
       let alphaSel = alphaPage.selection(for: alphaPage.bounds(for: .mediaBox)) {
        let created = PDFAnnotationOperations.highlight(alphaSel, color: .yellow, alpha: 0.8)
        check(!created.isEmpty, "highlight alpha: expected at least one annotation, got 0")
        if let first = created.first {
            let a = first.color.alphaComponent
            check(a >= 0.75 && a <= 0.85, "highlight alpha: expected alpha ~0.8, got \(a)")
        }
    } else {
        failures.append("highlight alpha: could not build selection")
    }
}

// snapshot/restore roundtrip: reloading from the entry snapshot discards
// annotations added after the snapshot was taken (the Cancel path).
do {
    let snapDoc = makeDocument(pageTexts: ["Snapshot roundtrip line"])
    if let snap = snapDoc.dataRepresentation(),
       let snapPage = snapDoc.page(at: 0),
       let snapSel = snapPage.selection(for: snapPage.bounds(for: .mediaBox)) {
        _ = PDFAnnotationOperations.highlight(snapSel, color: .yellow, alpha: 0.8)
        check(snapPage.annotations.count > 0,
              "snapshot restore: expected mutated page to have annotations, got 0")
        if let restored = PDFDocument(data: snap), let restoredPage = restored.page(at: 0) {
            check(restoredPage.annotations.isEmpty,
                  "snapshot restore: expected restored page to have 0 annotations, got \(restoredPage.annotations.count)")
        } else {
            failures.append("snapshot restore: could not reload PDFDocument from snapshot data")
        }
    } else {
        failures.append("snapshot restore: could not build snapshot/selection")
    }
}

// extractPages: builds a new document from the given 1-based page numbers, in order
let joinDoc = makeDocument(pageTexts: (1...8).map { "Page \($0)" })
let joined = PDFOperations.extractPages(joinDoc, pageNumbers: [2, 5, 7])
check(joined.pageCount == 3, "extractPages: expected 3 pages, got \(joined.pageCount)")
check(pageTexts(of: joined) == ["Page 2", "Page 5", "Page 7"],
      "extractPages: expected [Page 2, Page 5, Page 7], got \(pageTexts(of: joined))")

// TextStyle typography: addFreeText applies font, color, alignment and size.
do {
    let styleDoc = makeDocument(pageTexts: ["Style page"])
    if let stylePage = styleDoc.page(at: 0) {
        let style = TextStyle(fontName: "Helvetica-Bold", fontSize: 20, color: .systemRed, alignment: .center)
        let styled = PDFAnnotationOperations.addFreeText(
            on: stylePage, at: CGPoint(x: 40, y: 200), text: "Styled",
            style: style, size: CGSize(width: 300, height: 60))
        check((styled.font?.pointSize ?? 0) == 20,
              "addFreeText style: expected point size 20, got \(styled.font?.pointSize ?? 0)")
        check((styled.font?.fontName ?? "").contains("Helvetica"),
              "addFreeText style: expected Helvetica font, got \(styled.font?.fontName ?? "nil")")
        if let fc = styled.fontColor?.usingColorSpace(.deviceRGB),
           let red = NSColor.systemRed.usingColorSpace(.deviceRGB) {
            check(abs(fc.redComponent - red.redComponent) < 0.1
                  && abs(fc.greenComponent - red.greenComponent) < 0.1
                  && abs(fc.blueComponent - red.blueComponent) < 0.1,
                  "addFreeText style: fontColor not ~red, got \(fc)")
        } else {
            failures.append("addFreeText style: could not resolve fontColor components")
        }
        check(styled.alignment == .center,
              "addFreeText style: expected center alignment, got \(styled.alignment.rawValue)")
        check(styled.bounds.size == CGSize(width: 300, height: 60),
              "addFreeText style: expected 300x60 bounds, got \(styled.bounds.size)")
    } else {
        failures.append("addFreeText style: could not build page")
    }
}

// TextStyle override on replaceTextBlock: the text annotation uses the override
// font size, not the detected typography.
do {
    let doc = makeTextBlockDocument()
    if let page = doc.page(at: 0) {
        let blocks = PDFTextBlockDetector.blocks(on: page)
        if let target = blocks.first {
            let override = TextStyle(fontName: "Helvetica-Bold", fontSize: 33, color: .systemBlue, alignment: .center)
            let replacement = PDFAnnotationOperations.replaceTextBlock(
                target, on: page, with: "Overridden", style: override)
            check((replacement.text.font?.pointSize ?? 0) == 33,
                  "replaceTextBlock style: expected override size 33, got \(replacement.text.font?.pointSize ?? 0)")
            check(abs((replacement.text.font?.pointSize ?? 0) - target.fontSize) > 1,
                  "replaceTextBlock style: override size should differ from detected \(target.fontSize)")
            check(replacement.text.alignment == .center,
                  "replaceTextBlock style: expected center alignment, got \(replacement.text.alignment.rawValue)")
        } else {
            failures.append("replaceTextBlock style: no blocks detected")
        }
    } else {
        failures.append("replaceTextBlock style: no page")
    }
}

if failures.isEmpty {
    print("ALL CHECKS PASSED")
} else {
    print("FAILURES:")
    for f in failures { print(" - \(f)") }
    exit(1)
}
