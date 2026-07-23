import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindow: NSWindow?
    private var tutorialWindow: NSWindow?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @MainActor func showSettings() {
        let window = settingsWindow ?? makeWindow(
            title: L("settings.title"),
            content: SettingsView(),
            size: NSSize(width: 440, height: 560),
            resizable: false
        )
        settingsWindow = window
        present(window)
    }

    @MainActor func showTutorial() {
        let window = tutorialWindow ?? makeWindow(
            title: L("tutorial.title"),
            content: TutorialView(),
            size: NSSize(width: 580, height: 640),
            resizable: true
        )
        tutorialWindow = window
        present(window)
    }

    @MainActor private func makeWindow<Content: View>(
        title: String, content: Content, size: NSSize, resizable: Bool
    ) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = title
        window.styleMask = resizable ? [.titled, .closable, .resizable] : [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(size)
        window.center()
        return window
    }

    @MainActor private func present(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct FiScannerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        AppDefaults.registerFactory()
    }

    var body: some Scene {
        WindowGroup("fi-6110 Scanner") {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button(L("menu.settings")) { appDelegate.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button(L("menu.tutorial")) { appDelegate.showTutorial() }
                    .keyboardShortcut("?", modifiers: .command)
            }
        }
    }
}
