import AppKit
import PDFKit
import PDFStackKit
import SwiftUI

private enum EditMode: Equatable {
    case none
    case trim
    case split
    case markup
    case pages
}

struct PageGridView: View {
    @ObservedObject var appState: AppState
    let item: PDFItem

    @State private var mode: EditMode = .none
    @State private var trimStart: Int?
    @State private var trimEnd: Int?
    @State private var splitMarkers: Set<Int> = []
    @State private var pageSelection: Set<Int> = []
    @State private var markupInitialPageIndex: Int?
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var exportedURLs: [URL] = []
    @State private var successTask: Task<Void, Never>?

    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 8)]

    var body: some View {
        Group {
            if mode == .markup {
                MarkupView(appState: appState, item: item, onDone: resetModeState, initialPageIndex: markupInitialPageIndex)
            } else {
                VStack(spacing: 0) {
                    header
                    ScrollView {
                        gridContent
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Pheno.canvasBg)
                    messagesStrip
                    footer
                }
                .background(Pheno.canvasBg)
            }
        }
        .onChange(of: item.id) { _ in
            resetModeState()
            clearSuccess()
        }
    }

    @ViewBuilder
    private var gridContent: some View {
        if item.pageCount > 0 {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(1...item.pageCount, id: \.self) { pageNumber in
                    pageThumbnail(pageNumber)
                }
            }
            .padding(12)
        } else {
            Text("This PDF has no pages.")
                .font(.system(size: 13))
                .foregroundColor(Pheno.textDim)
                .padding()
        }
    }

    private func pageThumbnail(_ pageNumber: Int) -> some View {
        PageThumbnailView(
            document: item.document,
            pageNumber: pageNumber,
            isDimmed: isDimmed(pageNumber),
            isMarked: (mode == .split && splitMarkers.contains(pageNumber))
                || (mode == .pages && pageSelection.contains(pageNumber))
                || (mode == .none && pageSelection.contains(pageNumber)),
            isChecked: mode == .none && pageSelection.contains(pageNumber)
        )
        // Double-tap opens the editor at this page; registered before the
        // single-tap toggle so both gestures coexist.
        .onTapGesture(count: 2) {
            if mode == .none { enterMarkup(atPageIndex: pageNumber - 1) }
        }
        .onTapGesture {
            handleTap(pageNumber)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("\(item.displayName) · \(item.pageCount) page\(item.pageCount == 1 ? "" : "s")")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Pheno.textHigh)
                .lineLimit(1)
            Spacer()
            if mode == .none {
                PhenoModeButton(title: "Trim", disabled: pageSelection.isEmpty && item.pageCount < 2) { trimAction() }
                PhenoModeButton(title: "Split", disabled: pageSelection.isEmpty && item.pageCount < 2) { splitAction() }
                PhenoModeButton(title: "Join", disabled: pageSelection.count < 2) { joinAction() }
                PhenoModeButton(title: "Pages", disabled: item.pageCount < 1) { clearSuccess(); mode = .pages }
                PhenoModeButton(title: "Edit") { editAction() }
            }
        }
        .padding(EdgeInsets(top: 9, leading: 14, bottom: 9, trailing: 12))
        .frame(maxWidth: .infinity)
        .background(Pheno.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Pheno.border06).frame(height: 1)
        }
    }

    private func strip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 12))
            .frame(maxWidth: .infinity)
            .background(Pheno.panel)
            .overlay(alignment: .top) {
                Rectangle().fill(Pheno.border06).frame(height: 1)
            }
    }

    @ViewBuilder
    private var messagesStrip: some View {
        if errorMessage != nil || successMessage != nil {
            strip {
                HStack(spacing: 8) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 11))
                            .foregroundColor(Pheno.pink)
                    }
                    if let successMessage {
                        Text(successMessage)
                            .font(.system(size: 11))
                            .foregroundColor(Pheno.green)
                        Button("Reveal in Finder") { revealExportedFiles() }
                            .font(.system(size: 11))
                            .foregroundColor(Pheno.accentBright)
                            .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch mode {
        case .markup:
            EmptyView()
        case .none:
            if !pageSelection.isEmpty {
                strip {
                    HStack(spacing: 8) {
                        Text("\(pageSelection.count) page\(pageSelection.count == 1 ? "" : "s") selected.")
                            .font(.system(size: 11))
                            .foregroundColor(Pheno.textDim)
                        Spacer()
                        PhenoActionButton(title: "Clear") { pageSelection = [] }
                    }
                }
            }
        case .trim:
            strip {
                HStack(spacing: 8) {
                    Text(trimSummary)
                        .font(.system(size: 11))
                        .foregroundColor(Pheno.textDim)
                    Spacer()
                    PhenoActionButton(title: "Cancel") { resetModeState() }
                    PhenoActionButton(title: "Apply", kind: .primary, disabled: trimStart == nil || trimEnd == nil) { applyTrim() }
                }
            }
        case .split:
            strip {
                HStack(spacing: 8) {
                    Text("\(splitMarkers.count + 1) piece\(splitMarkers.count == 0 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundColor(Pheno.textDim)
                    Spacer()
                    PhenoActionButton(title: "Cancel") { resetModeState() }
                    PhenoActionButton(title: "Add Pieces to List", kind: .primary, disabled: splitMarkers.isEmpty) { confirmSplit(exportNow: false) }
                    PhenoActionButton(title: "Export Now…", kind: .primary, disabled: splitMarkers.isEmpty) { confirmSplit(exportNow: true) }
                }
            }
        case .pages:
            strip {
                HStack(spacing: 8) {
                    Text("\(pageSelection.count) page\(pageSelection.count == 1 ? "" : "s") selected")
                        .font(.system(size: 11))
                        .foregroundColor(Pheno.textDim)
                    Spacer()
                    PhenoActionButton(title: "Rotate Left", disabled: pageSelection.isEmpty) { applyRotate(by: -90) }
                    PhenoActionButton(title: "Rotate Right", disabled: pageSelection.isEmpty) { applyRotate(by: 90) }
                    PhenoActionButton(title: "Delete", kind: .destructive, disabled: pageSelection.isEmpty) { applyDelete() }
                    PhenoActionButton(title: "Extract to New PDF", kind: .primary, disabled: pageSelection.isEmpty) { applyExtract() }
                    PhenoActionButton(title: "Cancel") { resetModeState() }
                }
            }
        }
    }

    private var trimSummary: String {
        guard let start = trimStart, let end = trimEnd else {
            return "Click a start page, then an end page"
        }
        return "Keeping pages \(min(start, end))–\(max(start, end))"
    }

    private func isDimmed(_ pageNumber: Int) -> Bool {
        guard mode == .trim, let start = trimStart, let end = trimEnd else { return false }
        return !(min(start, end)...max(start, end)).contains(pageNumber)
    }

    private func handleTap(_ pageNumber: Int) {
        switch mode {
        case .none:
            if pageSelection.contains(pageNumber) {
                pageSelection.remove(pageNumber)
            } else {
                pageSelection.insert(pageNumber)
            }
        case .markup:
            return
        case .trim:
            if trimStart == nil || trimEnd != nil {
                trimStart = pageNumber
                trimEnd = nil
            } else {
                trimEnd = pageNumber
            }
        case .split:
            guard pageNumber < item.pageCount else { return }
            if splitMarkers.contains(pageNumber) {
                splitMarkers.remove(pageNumber)
            } else {
                splitMarkers.insert(pageNumber)
            }
        case .pages:
            if pageSelection.contains(pageNumber) {
                pageSelection.remove(pageNumber)
            } else {
                pageSelection.insert(pageNumber)
            }
        }
    }

    // With pages selected, trim immediately to the contiguous range spanning the
    // selection; with nothing selected, fall back to the interactive trim mode.
    private func trimAction() {
        clearSuccess()
        if pageSelection.isEmpty {
            mode = .trim
        } else {
            trimStart = pageSelection.min()
            trimEnd = pageSelection.max()
            applyTrim()
        }
    }

    // With pages selected, jump into split mode with the selection pre-set as
    // "split after" markers so the user still picks Add-to-List vs Export; with
    // nothing selected, enter the interactive split mode unchanged.
    private func splitAction() {
        clearSuccess()
        if !pageSelection.isEmpty {
            splitMarkers = pageSelection.filter { $0 < item.pageCount }
        }
        mode = .split
    }

    // Builds a new PDF from the selected pages in ascending order and inserts it
    // after the current item.
    private func joinAction() {
        clearSuccess()
        guard pageSelection.count >= 2 else { return }
        let joined = PDFOperations.extractPages(item.document, pageNumbers: pageSelection.sorted())
        appState.insertItem(after: item.id, document: joined, displayName: "\(item.displayName) (joined)")
        pageSelection = []
    }

    // Editing literally only the selected pages would require a detached temp
    // document whose edits can't merge back into the source — out of scope. The
    // faithful pragmatic reading is to open the editor at the first selected page
    // (page 1 when nothing is selected) and rely on the thumbnail strip for
    // navigation across the whole document.
    private func editAction() {
        clearSuccess()
        enterMarkup(atPageIndex: pageSelection.min().map { $0 - 1 })
    }

    private func applyTrim() {
        clearSuccess()
        guard let start = trimStart, let end = trimEnd else { return }
        let range = min(start, end)...max(start, end)
        do {
            let trimmed = try PDFOperations.trim(item.document, keepingPages: range)
            appState.updateDocument(id: item.id, document: trimmed)
            resetModeState()
        } catch {
            errorMessage = "Couldn't trim: \(error)"
        }
    }

    private func confirmSplit(exportNow: Bool) {
        if !exportNow { clearSuccess() }
        do {
            let pieces = try PDFOperations.split(item.document, afterPages: Array(splitMarkers))
            if exportNow {
                exportPieces(pieces)
            } else {
                appState.replaceItem(id: item.id, withDocuments: pieces)
            }
            resetModeState()
        } catch {
            errorMessage = "Couldn't split: \(error)"
        }
    }

    private func applyRotate(by degrees: Int) {
        clearSuccess()
        do {
            let rotated = try PDFOperations.rotate(item.document, pages: pageSelection, by: degrees)
            appState.updateDocument(id: item.id, document: rotated)
            resetModeState()
        } catch {
            errorMessage = "Couldn't rotate: \(error)"
        }
    }

    private func applyDelete() {
        clearSuccess()
        do {
            let remaining = try PDFOperations.delete(item.document, pages: pageSelection)
            appState.updateDocument(id: item.id, document: remaining)
            resetModeState()
        } catch PDFOperationError.wouldDeleteAllPages {
            errorMessage = "Can't delete every page"
        } catch {
            errorMessage = "Couldn't delete: \(error)"
        }
    }

    private func applyExtract() {
        clearSuccess()
        do {
            let extracted = try PDFOperations.extract(item.document, pages: pageSelection)
            appState.insertItem(after: item.id, document: extracted, displayName: "\(item.displayName) (extract)")
            resetModeState()
        } catch {
            errorMessage = "Couldn't extract: \(error)"
        }
    }

    private func exportPieces(_ pieces: [PDFDocument]) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = appState.lastSaveDirectory
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        var usedNames: Set<String> = []
        var failedNames: [String] = []
        var writtenURLs: [URL] = []
        for (index, piece) in pieces.enumerated() {
            let baseName = "\(item.displayName)-part\(index + 1)"
            var candidate = baseName
            var attempt = 1
            while usedNames.contains(candidate)
                || FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(candidate).pdf").path) {
                attempt += 1
                candidate = "\(baseName)-\(attempt)"
            }
            usedNames.insert(candidate)
            let destination = folder.appendingPathComponent("\(candidate).pdf")
            if !piece.write(to: destination) {
                failedNames.append("\(candidate).pdf")
            } else {
                writtenURLs.append(destination)
            }
        }
        if !failedNames.isEmpty {
            errorMessage = "Couldn't write: \(failedNames.joined(separator: ", "))"
        } else {
            appState.lastSaveDirectory = folder
            showSuccess(message: "Saved \(writtenURLs.count) file\(writtenURLs.count == 1 ? "" : "s")", urls: writtenURLs)
        }
    }

    private func showSuccess(message: String, urls: [URL]) {
        successMessage = message
        exportedURLs = urls
        successTask?.cancel()
        successTask = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            successMessage = nil
            exportedURLs = []
        }
    }

    private func clearSuccess() {
        successTask?.cancel()
        successTask = nil
        successMessage = nil
        exportedURLs = []
    }

    private func revealExportedFiles() {
        NSWorkspace.shared.activateFileViewerSelecting(exportedURLs)
    }

    private func enterMarkup(atPageIndex pageIndex: Int?) {
        markupInitialPageIndex = pageIndex
        mode = .markup
    }

    private func resetModeState() {
        mode = .none
        trimStart = nil
        trimEnd = nil
        splitMarkers = []
        pageSelection = []
        markupInitialPageIndex = nil
        errorMessage = nil
    }
}
