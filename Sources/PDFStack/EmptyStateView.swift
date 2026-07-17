import AppKit
import PDFStackKit
import SwiftUI
import UniformTypeIdentifiers

struct EmptyStateView: View {
    @ObservedObject var appState: AppState
    @StateObject private var importController: PDFImportController

    init(appState: AppState) {
        self.appState = appState
        _importController = StateObject(wrappedValue: PDFImportController(appState: appState))
    }

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 16) {
            dropZoneCard
            if let message = importController.message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(Pheno.pink)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Pheno.canvasBg)
        .contentShape(Rectangle())
        .sheet(isPresented: $importController.isPresentingPasswordSheet) {
            PasswordUnlockSheet(controller: importController)
        }
    }

    private var dropZoneCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 40))
                .foregroundColor(Pheno.textMid)
            Text("Drag and drop PDF files here, or click to browse.")
                .font(.system(size: 13))
                .foregroundColor(Pheno.textMid)
            Text("You can add more documents at any time from the sidebar.")
                .font(.system(size: 11))
                .foregroundColor(Pheno.textDim)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .frame(width: 420, height: 240)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    Color.white.opacity(0.15),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { addPDFs() }
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var cardFill: Color {
        if isHovering {
            return Pheno.elevated.opacity(0.4)
        }
        return Color.clear
    }

    private func addPDFs() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf]
        if panel.runModal() == .OK {
            importURLs(panel.urls)
        }
    }

    private func importURLs(_ urls: [URL]) {
        importController.importURLs(urls)
    }
}
