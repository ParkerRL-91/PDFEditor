import AppKit
import PDFStackKit
import SwiftUI

/// Routes Finder-driven opens (Open With, double-click, Dock drop) to the app's single
/// `AppState` instance. `application(_:open:)` can fire before the SwiftUI window (and thus
/// `ContentView`'s import controller) exists, so URLs are queued on `AppState.pendingOpenURLs`
/// rather than imported directly here — `ContentView` drains the queue once it's alive, which
/// also means files opened later while running flow through the same queue uniformly.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?

    func application(_ application: NSApplication, open urls: [URL]) {
        appState?.pendingOpenURLs.append(contentsOf: urls)
    }
}

@main
struct PDFStackApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // NSApp (an implicitly-unwrapped global) isn't populated yet when a SwiftUI
        // App's init() runs — NSApplication.shared lazily bootstraps it instead.
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .onAppear { appDelegate.appState = appState }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    appState.openFileMenuRequest += 1
                }
                .keyboardShortcut("o", modifiers: .command)
                Button("Save…") {
                    appState.saveMenuRequest += 1
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(appState.items.isEmpty)
            }
        }
    }
}
