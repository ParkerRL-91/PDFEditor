import AppKit
import PDFStackKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var appState: AppState
    @StateObject private var importController: PDFImportController
    @State private var dropTargeted = false

    init(appState: AppState) {
        self.appState = appState
        _importController = StateObject(wrappedValue: PDFImportController(appState: appState))
    }

    var body: some View {
        Group {
            if appState.items.isEmpty {
                EmptyStateView(appState: appState)
            } else {
                MainLayoutView(appState: appState)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(Pheno.chromeDeep)
        .background(FileDropCatcher(isTargeted: $dropTargeted) { urls in
            importController.importURLs(urls)
        })
        .overlay {
            if dropTargeted {
                dropIndicator
            }
        }
        .animation(.easeOut(duration: 0.15), value: dropTargeted)
        .preferredColorScheme(.dark)
        .navigationTitle(appState.selectedItem?.displayName ?? "PDF Stack")
        .onChange(of: appState.openFileMenuRequest) { _ in
            openFilePanel()
        }
        .onChange(of: appState.pendingOpenURLs) { urls in
            guard !urls.isEmpty else { return }
            appState.pendingOpenURLs = []
            importController.importURLs(urls)
        }
        .onAppear {
            guard !appState.pendingOpenURLs.isEmpty else { return }
            let urls = appState.pendingOpenURLs
            appState.pendingOpenURLs = []
            importController.importURLs(urls)
        }
        .sheet(isPresented: $importController.isPresentingPasswordSheet) {
            PasswordUnlockSheet(controller: importController)
        }
    }

    private var dropIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Pheno.accent.opacity(0.08))
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Pheno.accentBright, lineWidth: 2)
            Text("Drop PDF files to add them.")
                .font(.system(size: 13))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Pheno.accent)
                .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .padding(8)
        .allowsHitTesting(false)
    }

    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK else { return }
        importController.importURLs(panel.urls)
    }
}
