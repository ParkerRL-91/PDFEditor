import AppKit
import PDFKit
import PDFStackKit
import SwiftUI

struct SidebarRowView: View {
    @ObservedObject var appState: AppState
    let item: PDFItem
    @State private var isEditing = false
    @State private var editedName = ""
    @State private var thumbnail: NSImage?
    @State private var isHovering = false
    @FocusState private var isNameFieldFocused: Bool

    private var isSelected: Bool { item.id == appState.selectedItemID }

    var body: some View {
        HStack(spacing: 10) {
            thumbnailCard
            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    TextField("Name", text: $editedName, onCommit: commitRename)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Pheno.textHigh)
                        .textFieldStyle(.plain)
                        .focused($isNameFieldFocused)
                        .onExitCommand { cancelRename() }
                } else {
                    Text(item.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Pheno.textHigh)
                        .lineLimit(1)
                }
                Text("\(item.pageCount) page\(item.pageCount == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundColor(Pheno.textDim)
            }
            Spacer(minLength: 0)
            PhenoIconButton(systemName: "xmark", accessibilityLabel: "Remove \(item.displayName)") {
                appState.removeItem(id: item.id)
            }
        }
        .padding(EdgeInsets(top: 9, leading: 10, bottom: 9, trailing: 10))
        .background(isSelected || isHovering ? Pheno.selectedRow : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Pheno.accentBright, lineWidth: isSelected ? 1 : 0)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Rename") { beginRename() }
            Button("Duplicate") { appState.duplicateItem(id: item.id) }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.sourceURL])
            }
            Button("Remove") { appState.removeItem(id: item.id) }
        }
        .onAppear { loadThumbnailIfNeeded() }
        .onChange(of: ObjectIdentifier(item.document)) { _ in loadThumbnailIfNeeded() }
    }

    private var thumbnailCard: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.white
            }
        }
        .frame(width: 36, height: 46)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(Pheno.border08, lineWidth: 1)
        )
    }

    private func loadThumbnailIfNeeded() {
        guard let page = item.document.page(at: 0) else {
            thumbnail = nil
            return
        }
        thumbnail = page.thumbnail(of: CGSize(width: 72, height: 92), for: .mediaBox)
    }

    private func beginRename() {
        editedName = item.displayName
        isEditing = true
        isNameFieldFocused = true
    }

    private func commitRename() {
        guard isEditing else { return }
        appState.renameItem(id: item.id, to: editedName)
        isEditing = false
    }

    private func cancelRename() {
        isEditing = false
    }
}
