import PDFKit
import SwiftUI

struct PageThumbnailView: View {
    let document: PDFDocument
    let pageNumber: Int
    let isDimmed: Bool
    let isMarked: Bool
    /// When true (selection mode), a filled checkmark badge is drawn in the
    /// top-leading corner to mark the page as selected.
    var isChecked: Bool = false

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.white
            }
        }
        .frame(width: 90, height: 120)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(isMarked ? Pheno.accentBright : Pheno.border08, lineWidth: isMarked ? 2 : 1)
        )
        .overlay(alignment: .bottomTrailing) {
            Text("\(pageNumber)")
                .font(.system(size: 11).monospacedDigit())
                .padding(.vertical, 1)
                .padding(.horizontal, 5)
                .background(Pheno.chromeDeep.opacity(0.85))
                .foregroundColor(Pheno.textDim)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(4)
        }
        .overlay(alignment: .topLeading) {
            if isChecked {
                checkmarkBadge
                    .padding(4)
            }
        }
        .opacity(isDimmed ? 0.35 : 1.0)
        .onAppear { loadThumbnailIfNeeded() }
        .onChange(of: ObjectIdentifier(document)) { _ in loadThumbnailIfNeeded() }
    }

    private var checkmarkBadge: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(Pheno.accentBright)
            .background(Circle().fill(Pheno.chromeDeep))
    }

    // Cached in @State so toggling trim/split markers elsewhere in the grid
    // (which only changes isDimmed/isMarked) doesn't re-render this thumbnail
    // from scratch — only an actual document swap (e.g. after a trim) reloads it.
    private func loadThumbnailIfNeeded() {
        guard let page = document.page(at: pageNumber - 1) else {
            image = nil
            return
        }
        image = page.thumbnail(of: CGSize(width: 90, height: 120), for: .mediaBox)
    }
}
