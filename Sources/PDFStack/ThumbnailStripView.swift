import PDFKit
import SwiftUI

struct ThumbnailStripView: View {
    let document: PDFDocument
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            cards
        }
        .frame(width: 112)
        .background(Pheno.canvasBg)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Pheno.border06).frame(width: 1)
        }
    }

    private var cards: some View {
        VStack(spacing: 6) {
            ForEach(0..<max(document.pageCount, 0), id: \.self) { index in
                ThumbnailCard(
                    document: document,
                    pageIndex: index,
                    isSelected: selectedIndex == index
                )
                .onTapGesture { onSelect(index) }
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }
}

private struct ThumbnailCard: View {
    let document: PDFDocument
    let pageIndex: Int
    let isSelected: Bool

    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 5) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Color.white
                }
            }
            .frame(width: 66)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Pheno.accentBright, lineWidth: isSelected ? 2 : 0)
            )
            .shadow(color: .black.opacity(isSelected ? 0.4 : 0), radius: isSelected ? 4 : 0, x: 0, y: 3)

            Text("\(pageIndex + 1)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(Pheno.textDim)
        }
        .onAppear { loadThumbnailIfNeeded() }
        .onChange(of: ObjectIdentifier(document)) { _ in loadThumbnailIfNeeded() }
    }

    private func loadThumbnailIfNeeded() {
        guard let page = document.page(at: pageIndex) else {
            image = nil
            return
        }
        image = page.thumbnail(of: CGSize(width: 132, height: 176), for: .mediaBox)
    }
}
