import Foundation
import PDFStackKit
import SwiftUI
import UniformTypeIdentifiers

/// Shared import behavior for the two drop/pick surfaces (EmptyStateView, SidebarView):
/// turns `AppState.addPDF` results into an inline message and drives the
/// password-unlock sheet for locked PDFs.
@MainActor
final class PDFImportController: ObservableObject {
    @Published var message: String?
    @Published var isPresentingPasswordSheet = false
    @Published var passwordAttempt = ""
    @Published var passwordErrorMessage: String?

    private var pendingLockedURL: URL?
    private unowned let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    /// Shared drop handler for both drop surfaces. Finder file drags often
    /// advertise only `public.file-url` (not `com.adobe.pdf`), so both
    /// `.fileURL` and `.pdf` must be accepted in `.onDrop` for the drop —
    /// and its `isTargeted` highlight — to fire at all. Returns `true` only
    /// when at least one provider carries a file URL or PDF, then resolves the
    /// URLs off the main thread and imports the PDFs back on the main queue.
    @discardableResult
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        let accepted = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
        }
        guard !accepted.isEmpty else { return false }

        let group = DispatchGroup()
        let lock = NSLock()
        var resolved: [URL] = []
        for provider in accepted {
            group.enter()
            Self.resolveURL(from: provider) { url in
                if let url {
                    lock.lock()
                    resolved.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            let pdfs = resolved.filter { $0.pathExtension.lowercased() == "pdf" }
            guard !pdfs.isEmpty else { return }
            self?.importURLs(pdfs)
        }
        return true
    }

    /// Resolves a drop provider to a file URL. Prefers the file-URL data
    /// representation (reliable for Finder drags that expose only
    /// `public.file-url`), falling back to `loadObject(ofClass: URL.self)`.
    static func resolveURL(from provider: NSItemProvider, completion: @escaping (URL?) -> Void) {
        let fileURLType = UTType.fileURL.identifier
        if provider.hasItemConformingToTypeIdentifier(fileURLType) {
            provider.loadDataRepresentation(forTypeIdentifier: fileURLType) { data, _ in
                if let data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    completion(url)
                } else {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url {
                            completion(url)
                        } else {
                            loadPDFFileRepresentation(from: provider, completion: completion)
                        }
                    }
                }
            }
        } else {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    completion(url)
                } else {
                    loadPDFFileRepresentation(from: provider, completion: completion)
                }
            }
        }
    }

    /// Final fallback for providers that expose only `com.adobe.pdf` with no
    /// file-url representation. `loadFileRepresentation` hands back an ephemeral
    /// URL that is deleted the moment the callback returns, so the bytes must be
    /// copied to a stable temp file inside the callback before delivery.
    private static func loadPDFFileRepresentation(from provider: NSItemProvider, completion: @escaping (URL?) -> Void) {
        let pdfType = UTType.pdf.identifier
        guard provider.hasItemConformingToTypeIdentifier(pdfType) else {
            completion(nil)
            return
        }
        _ = provider.loadFileRepresentation(forTypeIdentifier: pdfType) { url, _ in
            guard let url else {
                completion(nil)
                return
            }
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("Dropped-\(UUID().uuidString).pdf")
            do {
                try FileManager.default.copyItem(at: url, to: tempURL)
                completion(tempURL)
            } catch {
                completion(nil)
            }
        }
    }

    func importURLs(_ urls: [URL]) {
        var messages: [String] = []
        for url in urls {
            let result = appState.addPDF(at: url)
            switch result {
            case .added:
                break
            case .duplicate:
                messages.append("Already added: \(url.lastPathComponent)")
            case .locked:
                pendingLockedURL = url
                passwordAttempt = ""
                passwordErrorMessage = nil
                isPresentingPasswordSheet = true
            case .restricted:
                messages.append("\(url.lastPathComponent) is protected and can't be edited")
            case .unreadable:
                messages.append("Couldn't open: \(url.lastPathComponent)")
            }
        }
        message = messages.isEmpty ? nil : messages.joined(separator: "; ")
    }

    func unlock() {
        guard let url = pendingLockedURL else { return }
        switch appState.addPDF(at: url, password: passwordAttempt) {
        case .added:
            isPresentingPasswordSheet = false
            pendingLockedURL = nil
            passwordAttempt = ""
            passwordErrorMessage = nil
        case .locked:
            passwordErrorMessage = "Wrong password"
        case .restricted:
            isPresentingPasswordSheet = false
            pendingLockedURL = nil
            passwordAttempt = ""
            message = "\(url.lastPathComponent) is protected and can't be edited"
        case .duplicate:
            isPresentingPasswordSheet = false
            pendingLockedURL = nil
            passwordAttempt = ""
            message = "Already added: \(url.lastPathComponent)"
        case .unreadable:
            isPresentingPasswordSheet = false
            pendingLockedURL = nil
            passwordAttempt = ""
            message = "Couldn't open: \(url.lastPathComponent)"
        }
    }

    func cancelPasswordSheet() {
        isPresentingPasswordSheet = false
        pendingLockedURL = nil
        passwordAttempt = ""
        passwordErrorMessage = nil
    }
}

struct PasswordUnlockSheet: View {
    @ObservedObject var controller: PDFImportController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This PDF is password-protected")
                .font(.headline)
            SecureField("Password", text: $controller.passwordAttempt)
                .textFieldStyle(.roundedBorder)
                .onSubmit { controller.unlock() }
            if let passwordErrorMessage = controller.passwordErrorMessage {
                Text(passwordErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { controller.cancelPasswordSheet() }
                Button("Unlock") { controller.unlock() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 300)
    }
}
