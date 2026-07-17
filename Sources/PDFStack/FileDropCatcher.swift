import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Window-wide AppKit drag destination. SwiftUI's `.onDrop` proved unreliable
/// once documents are loaded: the sidebar `List` is NSTableView-backed and
/// swallows external drags, and the page-grid detail pane has no drop handler,
/// so drags over most of the window were refused. Mounted as a background
/// layer, this view still receives drags anywhere over the window because
/// AppKit drag-destination hit-testing only considers views registered for
/// dragged types -- and because it never draws or handles mouse events, it
/// does not interfere with the SwiftUI content in front of it.
struct FileDropCatcher: NSViewRepresentable {
    @Binding var isTargeted: Bool
    let onDrop: ([URL]) -> Void

    func makeNSView(context: Context) -> DropView {
        let view = DropView()
        view.isTargetedBinding = { self.isTargeted = $0 }
        view.onDrop = onDrop
        view.registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("com.adobe.pdf")])
        return view
    }

    func updateNSView(_ nsView: DropView, context: Context) {
        nsView.isTargetedBinding = { self.isTargeted = $0 }
        nsView.onDrop = onDrop
    }

    final class DropView: NSView {
        var isTargetedBinding: ((Bool) -> Void)?
        var onDrop: (([URL]) -> Void)?

        private static let readingOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        private static let pdfDataType = NSPasteboard.PasteboardType("com.adobe.pdf")

        private func allURLs(from info: NSDraggingInfo) -> [URL] {
            info.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: Self.readingOptions
            ) as? [URL] ?? []
        }

        private func pdfURLs(from info: NSDraggingInfo) -> [URL] {
            allURLs(from: info).filter { $0.pathExtension.lowercased() == "pdf" }
        }

        private func hasPDFData(_ info: NSDraggingInfo) -> Bool {
            info.draggingPasteboard.data(forType: Self.pdfDataType) != nil
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            dragOperation(for: sender)
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            dragOperation(for: sender)
        }

        private func dragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
            if pdfURLs(from: sender).isEmpty && !hasPDFData(sender) {
                isTargetedBinding?(false)
                return []
            }
            isTargetedBinding?(true)
            return .copy
        }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            isTargetedBinding?(false)
        }

        override func draggingEnded(_ sender: NSDraggingInfo) {
            isTargetedBinding?(false)
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            var urls = pdfURLs(from: sender)
            isTargetedBinding?(false)

            // Fallback: SwiftUI-style item providers can expose only raw
            // `com.adobe.pdf` data with no file-url representation. Persist the
            // bytes to a temp file and deliver that URL so the rest of the
            // import pipeline (which expects file URLs) works unchanged.
            if urls.isEmpty, let data = sender.draggingPasteboard.data(forType: Self.pdfDataType) {
                let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("Dropped-\(UUID().uuidString).pdf")
                if (try? data.write(to: tempURL)) != nil {
                    urls = [tempURL]
                }
            }

            guard !urls.isEmpty else { return false }
            if Thread.isMainThread {
                onDrop?(urls)
            } else {
                DispatchQueue.main.async { [onDrop, urls] in onDrop?(urls) }
            }
            return true
        }
    }
}
