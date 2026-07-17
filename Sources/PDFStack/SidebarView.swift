import AppKit
import PDFKit
import PDFStackKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @ObservedObject var appState: AppState
    @StateObject private var importController: PDFImportController
    @State private var showingSaveOptions = false
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""
    @State private var saveSuccessMessage: String?
    @State private var savedURLs: [URL] = []
    @State private var saveSuccessTask: Task<Void, Never>?

    init(appState: AppState) {
        self.appState = appState
        _importController = StateObject(wrappedValue: PDFImportController(appState: appState))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                EyebrowLabel("Documents")
                Text("\(appState.items.count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(Pheno.textDim)
                Spacer()
                PhenoIconButton(systemName: "plus", accessibilityLabel: "Add PDFs") {
                    addMorePDFs()
                }
            }
            .padding(EdgeInsets(top: 14, leading: 14, bottom: 0, trailing: 12))

            Text("Documents are merged top to bottom in this order.")
                .font(.system(size: 11))
                .foregroundColor(Pheno.textDim)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 6, leading: 14, bottom: 10, trailing: 14))

            if let message = importController.message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(Pheno.pink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
            if let saveSuccessMessage {
                HStack(spacing: 8) {
                    Text(saveSuccessMessage)
                        .font(.system(size: 11))
                        .foregroundColor(Pheno.green)
                    Button("Reveal in Finder") { revealSavedFiles() }
                        .font(.system(size: 11))
                        .foregroundColor(Pheno.accentBright)
                        .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }

            List {
                ForEach(appState.items) { item in
                    SidebarRowView(appState: appState, item: item)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                        .onTapGesture {
                            appState.selectedItemID = item.id
                        }
                }
                .onMove { source, destination in
                    appState.moveItems(fromOffsets: source, toOffset: destination)
                }
                // The window-level FileDropCatcher (ContentView) cannot receive
                // drops over this area: the NSTableView backing the List is itself
                // a registered drag destination (for .onMove reordering) and sits in
                // front of the background catcher, so it takes precedence here.
                // .onInsert hooks the table's own drag path so external Finder drags
                // over the list still import.
                .onInsert(of: [UTType.fileURL, UTType.pdf]) { _, providers in
                    importController.handleDrop(providers: providers)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Pheno.panel)

            PhenoAccentButton(title: "Save PDFs", systemImage: "square.and.arrow.down", fullWidth: true) {
                showingSaveOptions = true
            }
            .padding(EdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12))
            .confirmationDialog("Save", isPresented: $showingSaveOptions) {
                Button("Save Combined PDF…") { saveCombined() }
                Button("Save Each Separately…") { saveSeparately() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .background(Pheno.panel)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Pheno.border06).frame(width: 1)
        }
        .alert("Save Failed", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
        .sheet(isPresented: $importController.isPresentingPasswordSheet) {
            PasswordUnlockSheet(controller: importController)
        }
        .onChange(of: appState.saveMenuRequest) { _ in
            guard !appState.items.isEmpty else { return }
            showingSaveOptions = true
        }
    }

    private func addMorePDFs() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK else { return }
        importURLs(panel.urls)
    }

    private func importURLs(_ urls: [URL]) {
        importController.importURLs(urls)
    }

    private func saveCombined() {
        clearSaveSuccess()
        let merged = PDFOperations.merge(appState.items.map { $0.document })
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Combined.pdf"
        panel.directoryURL = appState.lastSaveDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !merged.write(to: url) {
            saveErrorMessage = "Couldn't write to \(url.path)."
            showingSaveError = true
        } else {
            appState.lastSaveDirectory = url.deletingLastPathComponent()
            showSaveSuccess(message: "Saved \(url.lastPathComponent)", urls: [url])
        }
    }

    private func saveSeparately() {
        clearSaveSuccess()
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
        for item in appState.items {
            var candidate = item.displayName
            var attempt = 1
            while usedNames.contains(candidate)
                || FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(candidate).pdf").path) {
                attempt += 1
                candidate = "\(item.displayName)-\(attempt)"
            }
            usedNames.insert(candidate)
            let destination = folder.appendingPathComponent("\(candidate).pdf")
            if !item.document.write(to: destination) {
                failedNames.append("\(candidate).pdf")
            } else {
                writtenURLs.append(destination)
            }
        }
        if !failedNames.isEmpty {
            saveErrorMessage = "Couldn't write: \(failedNames.joined(separator: ", "))"
            showingSaveError = true
        } else {
            appState.lastSaveDirectory = folder
            showSaveSuccess(message: "Saved \(writtenURLs.count) file\(writtenURLs.count == 1 ? "" : "s")", urls: writtenURLs)
        }
    }

    private func showSaveSuccess(message: String, urls: [URL]) {
        saveSuccessMessage = message
        savedURLs = urls
        saveSuccessTask?.cancel()
        saveSuccessTask = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            saveSuccessMessage = nil
            savedURLs = []
        }
    }

    private func clearSaveSuccess() {
        saveSuccessTask?.cancel()
        saveSuccessTask = nil
        saveSuccessMessage = nil
        savedURLs = []
    }

    private func revealSavedFiles() {
        NSWorkspace.shared.activateFileViewerSelecting(savedURLs)
    }
}
