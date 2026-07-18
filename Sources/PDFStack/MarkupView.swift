import AppKit
import PDFKit
import PDFStackKit
import SwiftUI

private enum PlacingTool {
    case note
}

struct MarkupView: View {
    @ObservedObject var appState: AppState
    let item: PDFItem
    let onDone: () -> Void
    /// 0-based page to open the editor at when entered by clicking a specific
    /// page thumbnail; nil enters at the document's first page.
    var initialPageIndex: Int?

    @StateObject private var session: MarkupSession

    init(appState: AppState, item: PDFItem, onDone: @escaping () -> Void, initialPageIndex: Int? = nil) {
        self.appState = appState
        self.item = item
        self.onDone = onDone
        self.initialPageIndex = initialPageIndex
        self._session = StateObject(wrappedValue: MarkupSession())
    }

    @State private var currentSelection: PDFSelection?
    @State private var pdfView: PDFView?
    @State private var placingTool: PlacingTool?
    @State private var isErasing = false
    @State private var pendingPlacement: (page: PDFPage, point: CGPoint)?
    @State private var pendingText: String = ""
    @State private var editingAnnotation: PDFAnnotation?
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            MarkupToolbarView(session: session, onSave: save)
            HStack(spacing: 0) {
                ThumbnailStripView(
                    document: item.document,
                    selectedIndex: session.currentPageIndex,
                    onSelect: goToPage
                )
                canvas
                inspector
            }
        }
        .background(Pheno.chromeDeep)
        // The session's activeTool is the single UI source of truth for tool
        // selection; it is mapped onto the existing arm/disarm placement
        // mechanics here so every tool change still flows through arm/disarm
        // (see the invariant comments on those helpers below).
        .onChange(of: session.activeTool) { applyTool($0) }
        .onAppear {
            // Snapshot on entry so Cancel can discard the whole session by
            // reloading the document from these bytes.
            session.entrySnapshot = item.document.dataRepresentation()
            session.refreshAnnotations(document: item.document)
        }
        .alert("Save Failed", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
    }

    private var canvas: some View {
        ZStack {
            PDFKitRepresentable(
                document: item.document,
                currentSelection: $currentSelection,
                onPageClick: { page, point in handlePageClick(page: page, point: point) },
                onViewCreated: { view in
                    pdfView = view
                    if let index = initialPageIndex, let page = item.document.page(at: index) {
                        view.go(to: page)
                        session.currentPageIndex = index
                    }
                },
                showTextBlockOutlines: session.activeTool == .editText,
                onPageChanged: { index in session.currentPageIndex = index },
                onSelectionEnded: { selection in handleSelectionEnded(selection) }
            )
            // The on-page editor is mounted only while an inline edit is open,
            // sitting above the canvas but passing outside-clicks through to the
            // PDFView so the page-click recognizer can commit (see handlePageClick).
            if session.inlineEdit != nil, let pdfView {
                InlineTextEditorOverlay(
                    session: session,
                    pdfView: pdfView,
                    onCommit: { commitInlineEdit() },
                    onCancel: { cancelInlineEdit() }
                )
            }
        }
        // The page sits 24pt below the toolbar.
        .padding(EdgeInsets(top: 24, leading: 24, bottom: 0, trailing: 24))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Pheno.canvasBg)
    }

    // Tool style controls, live annotations list, and Cancel/Done footer. Markup
    // tools apply on drag-release (see handleSelectionEnded); the placement/edit
    // popovers remain anchored to the inspector column.
    private var inspector: some View {
        MarkupInspectorView(
            session: session,
            onSelect: scrollToAnnotation,
            onCancel: cancelSession,
            onDone: {
                // Done commits an open inline edit first, then leaves markup.
                if session.inlineEdit != nil { commitInlineEdit() }
                onDone()
            },
            onCommitInline: commitInlineEdit
        )
        .popover(isPresented: isNotePopoverPresented) { placementPopoverContent }
    }

    private func scrollToAnnotation(_ entry: AnnotationEntry) {
        pdfView?.go(to: entry.annotation.bounds, on: entry.page)
    }

    private var isMarkupTool: Bool {
        switch session.activeTool {
        case .highlight, .underline, .strike: return true
        default: return false
        }
    }

    // The placement popover is anchored to the inspector column, not to the click
    // location on the page.
    // The click is captured via a native NSClickGestureRecognizer on the real
    // PDFView (see PDFKitRepresentable), which only yields a page-space point --
    // there is no cheap, reliable way to convert that back into a SwiftUI
    // view-space anchor for a scrolled/zoomed PDFView. Anchoring to a stable
    // chrome element is predictable and avoids AppKit/SwiftUI coordinate
    // bridging entirely; the annotation itself still lands exactly at the
    // clicked page-space point.
    //
    // `arm`/`disarm` are the ONLY places that reset `pendingPlacement`/
    // `pendingText`, and every path that changes `placingTool` (tool selection
    // via applyTool, the inspector Cancel) goes through one of them. This is
    // deliberate: a `.popover`'s `Binding`'s `set` closure only fires when
    // SwiftUI itself decides to dismiss the popover (Escape, click-away) --
    // it is NOT called when the app changes the underlying state directly
    // (e.g. switching tools just reassigns `placingTool`, which SwiftUI reads
    // as a reason to animate the old popover closed, but nothing calls the old
    // popover's `set(false)` to "notify" it). If `pendingText` were cleared
    // only inside these bindings' `set` closures, switching tools directly
    // would leave stale draft text behind for the next placement. Routing every
    // tool change through `arm`/`disarm` closes that gap regardless of which UI
    // path triggered it.
    private var isNotePopoverPresented: Binding<Bool> {
        Binding(
            get: {
                (pendingPlacement != nil && placingTool == .note)
                    || (editingAnnotation != nil && editingAnnotation?.type == "Text")
            },
            set: { isPresented in
                if !isPresented { disarm() }
            }
        )
    }

    @ViewBuilder
    private var placementPopoverContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Note text", text: $pendingText)
                .frame(minWidth: 220)
            HStack {
                Button("Cancel") { disarm() }
                Spacer()
                Button(editingAnnotation != nil ? "Save" : "Add") {
                    confirmPlacement()
                }
                .disabled(pendingText.isEmpty)
            }
        }
        .padding(12)
    }

    private func goToPage(_ index: Int) {
        guard let pdfView, let page = item.document.page(at: index) else { return }
        pdfView.go(to: page)
        session.currentPageIndex = index
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(item.displayName).pdf"
        panel.directoryURL = appState.lastSaveDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if item.document.write(to: url) {
            appState.lastSaveDirectory = url.deletingLastPathComponent()
        } else {
            saveErrorMessage = "Couldn't write to \(url.path)."
            showingSaveError = true
        }
    }

    /// Cancel discards the whole session: reload the document from the entry
    /// snapshot and swap it back into AppState, then leave markup.
    private func cancelSession() {
        if let snapshot = session.entrySnapshot,
           let restored = PDFDocument(data: snapshot) {
            appState.updateDocument(id: item.id, document: restored)
        }
        onDone()
    }

    /// Maps a `MarkupSession` tool onto the existing arm/disarm placement
    /// mechanics. Highlight/Underline/Strike stay in the select-then-Apply flow
    /// (disarmed placement state); Note arms its click-placement popover; Erase
    /// arms hit-test removal; Text/Edit Text drive inline editing straight from
    /// `session.activeTool` in `handlePageClick`, so they only need placement
    /// state cleared.
    ///
    /// Switching tools commits any open inline edit (never discards it) -- Esc
    /// is the only path that cancels an edit, handled inside the editor.
    private func applyTool(_ tool: MarkupTool) {
        if session.inlineEdit != nil { commitInlineEdit() }
        switch tool {
        case .highlight, .underline, .strike, .text, .editText:
            disarm()
        case .note:
            arm(.note)
        case .erase:
            armErase()
        }
    }

    /// Drag-to-apply: when a markup tool is armed, a finished text-selection drag
    /// applies the annotation immediately in the active swatch color at the
    /// session opacity, then clears the selection.
    private func handleSelectionEnded(_ selection: PDFSelection) {
        guard isMarkupTool else { return }
        let color = session.activeSwatch.nsColor
        let alpha = CGFloat(session.opacity)
        let created: [PDFAnnotation]
        switch session.activeTool {
        case .highlight: created = PDFAnnotationOperations.highlight(selection, color: color, alpha: alpha)
        case .underline: created = PDFAnnotationOperations.underline(selection, color: color, alpha: alpha)
        case .strike: created = PDFAnnotationOperations.strikeThrough(selection, color: color, alpha: alpha)
        default: return
        }
        created.forEach { session.recordCreated($0) }
        refreshAnnotations(on: selection.pages)
        clearSelection()
    }

    /// Removes `annotation` and, for Edit Text pairs, its partner. The cover
    /// square and FreeText created by `replaceTextBlock` share identical bounds
    /// on the same page, so erasing either one also removes the matching
    /// counterpart (found by userName tag + bounds) to avoid orphans.
    private func eraseWithPair(_ annotation: PDFAnnotation, on page: PDFPage) {
        let partnerUserName: String?
        switch annotation.userName {
        case "PDFStack.editText": partnerUserName = "PDFStack.editCover"
        case "PDFStack.editCover": partnerUserName = "PDFStack.editText"
        default: partnerUserName = nil
        }
        if let partnerUserName,
           let partner = pairedAnnotation(for: annotation, on: page, userName: partnerUserName) {
            PDFAnnotationOperations.remove(partner, from: page)
        }
        PDFAnnotationOperations.remove(annotation, from: page)
    }

    private func pairedAnnotation(for annotation: PDFAnnotation, on page: PDFPage, userName: String) -> PDFAnnotation? {
        page.annotations.first { candidate in
            candidate !== annotation
                && candidate.userName == userName
                && boundsApproximatelyEqual(candidate.bounds, annotation.bounds)
        }
    }

    private func boundsApproximatelyEqual(_ a: CGRect, _ b: CGRect, epsilon: CGFloat = 0.5) -> Bool {
        abs(a.minX - b.minX) < epsilon
            && abs(a.minY - b.minY) < epsilon
            && abs(a.width - b.width) < epsilon
            && abs(a.height - b.height) < epsilon
    }

    private func handlePageClick(page: PDFPage, point: CGPoint) {
        // A click outside the on-page editor commits the open edit first, then
        // the same click proceeds (so it can start a fresh edit or placement).
        if session.inlineEdit != nil {
            commitInlineEdit()
        }

        if isErasing {
            if let annotation = page.annotation(at: point) {
                eraseWithPair(annotation, on: page)
                refreshAnnotations(on: [page])
            }
            return
        }

        switch session.activeTool {
        case .text:
            beginInlineNewText(page: page, at: point)
            return
        case .editText:
            // A FreeText annotation (including our own edited-block text) re-edits
            // in place; otherwise a detected block starts a block replacement.
            if let annotation = page.annotation(at: point), annotation.type == "FreeText" {
                beginInlineEditFreeText(annotation, on: page)
            } else if let block = PDFTextBlockDetector.block(at: point, on: page) {
                beginInlineEditBlock(block, on: page)
            }
            return
        default:
            break
        }

        guard placingTool != nil else {
            // No placement tool armed: click an existing note to edit it in the
            // popover, or an existing text box to edit it inline.
            if let annotation = page.annotation(at: point) {
                if annotation.type == "Text" {
                    beginEditing(annotation)
                } else if annotation.type == "FreeText" {
                    beginInlineEditFreeText(annotation, on: page)
                }
            }
            return
        }
        pendingPlacement = (page: page, point: point)
    }

    private func confirmPlacement() {
        if let annotation = editingAnnotation {
            PDFAnnotationOperations.setContents(pendingText, of: annotation)
            let page = annotation.page
            disarm()
            if let page {
                refreshAnnotations(on: [page])
            }
            return
        }

        guard let pending = pendingPlacement, placingTool == .note else { return }
        let created = PDFAnnotationOperations.addNote(on: pending.page, at: pending.point, text: pendingText)
        session.recordCreated(created)
        refreshAnnotations(on: [pending.page])
        disarm()
    }

    // MARK: - Inline text editing

    private func beginInlineNewText(page: PDFPage, at point: CGPoint) {
        session.inlineEdit = InlineEdit(
            kind: .newText(pagePoint: point),
            page: page,
            text: "",
            style: session.textStyle
        )
    }

    private func beginInlineEditBlock(_ block: TextBlock, on page: PDFPage) {
        let style = TextStyle(
            fontName: block.fontName,
            fontSize: block.fontSize,
            color: block.textColor ?? .black,
            alignment: .natural
        )
        session.textStyle = style
        session.inlineEdit = InlineEdit(kind: .editBlock(block), page: page, text: block.text, style: style)
    }

    private func beginInlineEditFreeText(_ annotation: PDFAnnotation, on page: PDFPage) {
        let style = TextStyle(
            fontName: annotation.font?.fontName,
            fontSize: annotation.font?.pointSize ?? 14,
            color: annotation.fontColor ?? .black,
            alignment: annotation.alignment
        )
        session.textStyle = style
        session.inlineEdit = InlineEdit(
            kind: .editFreeText(annotation),
            page: page,
            text: annotation.contents ?? "",
            style: style
        )
    }

    /// Commits the open inline edit through the same registry path the popover
    /// flows used (`recordCreated` + `refreshAnnotations`). Empty text cancels:
    /// no new box, no block change, no annotation update.
    private func commitInlineEdit() {
        guard let edit = session.inlineEdit else { return }
        session.inlineEdit = nil
        let page = edit.page
        let trimmed = edit.text.trimmingCharacters(in: .whitespacesAndNewlines)

        let rect = InlineTextEditorOverlay.pageRect(for: edit)
        switch edit.kind {
        case .newText:
            guard !trimmed.isEmpty else { return }
            let point: CGPoint
            if case .newText(let pagePoint) = edit.kind { point = pagePoint } else { return }
            let created = PDFAnnotationOperations.addFreeText(
                on: page, at: point, text: edit.text, style: edit.style, size: rect.size
            )
            // The editor may have been dragged/grown away from the default box;
            // pin the committed annotation to the editor's final rect.
            created.bounds = rect
            session.recordCreated(created)
            refreshAnnotations(on: [page])
        case .editBlock(let block):
            guard !trimmed.isEmpty else { return }
            let replacement = PDFAnnotationOperations.replaceTextBlock(
                block, on: page, with: edit.text, style: edit.style, textRect: rect
            )
            session.recordCreated(replacement.text)
            refreshAnnotations(on: [page])
        case .editFreeText(let annotation):
            guard !trimmed.isEmpty else { return }
            annotation.contents = edit.text
            annotation.font = edit.style.font
            annotation.fontColor = edit.style.color
            annotation.alignment = edit.style.alignment
            annotation.bounds = rect
            refreshAnnotations(on: [page])
        }
    }

    private func cancelInlineEdit() {
        session.inlineEdit = nil
    }

    // PDFView does NOT repaint on its own when annotations are added or removed
    // programmatically -- Apple documents annotationsChanged(on:) as the app's
    // responsibility after any programmatic annotation mutation. Without this,
    // markup is written into the document (it saves correctly and renders in
    // page.draw) but stays invisible in the live view until something else
    // forces a redraw (scroll, zoom, mode switch).
    private func refreshAnnotations(on pages: [PDFPage]) {
        guard let pdfView else { return }
        for page in pages {
            pdfView.annotationsChanged(on: page)
        }
        pdfView.documentView?.needsDisplay = true
        session.refreshAnnotations(document: item.document)
    }

    /// Arms `tool`, resetting any in-progress placement from a previously
    /// armed tool. Always route tool changes through this (never assign
    /// `placingTool` directly) so `pendingPlacement`/`pendingText` can never
    /// go stale across a tool switch.
    private func arm(_ tool: PlacingTool) {
        placingTool = tool
        isErasing = false
        pendingPlacement = nil
        pendingText = ""
        editingAnnotation = nil
    }

    /// Arms erase mode. Routed like `arm(_:)`/`disarm()` so pending
    /// placement/edit state can never go stale across a tool switch.
    private func armErase() {
        placingTool = nil
        isErasing = true
        pendingPlacement = nil
        pendingText = ""
        editingAnnotation = nil
    }

    /// Clears the armed tool and any in-progress placement or edit. Always route
    /// disarming through this (never assign `placingTool = nil` directly)
    /// for the same reason as `arm(_:)`.
    private func disarm() {
        placingTool = nil
        isErasing = false
        pendingPlacement = nil
        pendingText = ""
        editingAnnotation = nil
    }

    /// Opens the placement popover pre-filled with an existing note/text box's
    /// contents, in editing mode. Routed through the same `pendingText` state
    /// the placement flow uses; `confirmPlacement` branches on `editingAnnotation`
    /// to update the existing annotation instead of creating a new one.
    private func beginEditing(_ annotation: PDFAnnotation) {
        placingTool = nil
        isErasing = false
        pendingPlacement = nil
        pendingText = annotation.contents ?? ""
        editingAnnotation = annotation
    }

    private func clearSelection() {
        pdfView?.clearSelection()
        currentSelection = nil
    }
}
