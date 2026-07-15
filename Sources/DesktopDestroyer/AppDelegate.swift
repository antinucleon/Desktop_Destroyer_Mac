import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var gameViewController: GameViewController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()

        let controller = GameViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Desktop Destroyer"
        window.subtitle = "Metal Edition"
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1_180, height: 760))
        window.minSize = NSSize(width: 840, height: 620)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.fullScreenPrimary]
        window.center()
        window.makeKeyAndOrderFront(nil)

        gameViewController = controller
        self.window = window
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func configureMenu() {
        let mainMenu = NSMenu()

        let applicationItem = NSMenuItem()
        mainMenu.addItem(applicationItem)
        let applicationMenu = NSMenu()
        applicationItem.submenu = applicationMenu
        applicationMenu.addItem(withTitle: "About Desktop Destroyer", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Quit Desktop Destroyer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let gameItem = NSMenuItem()
        mainMenu.addItem(gameItem)
        let gameMenu = NSMenu(title: "Game")
        gameItem.submenu = gameMenu
        let capture = gameMenu.addItem(withTitle: "Capture Desktop", action: #selector(captureDesktop), keyEquivalent: "c")
        capture.keyEquivalentModifierMask = [.command]
        let reset = gameMenu.addItem(withTitle: "Reset Surface", action: #selector(resetSurface), keyEquivalent: "r")
        reset.keyEquivalentModifierMask = [.command]

        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f").keyEquivalentModifierMask = [.control, .command]

        NSApplication.shared.mainMenu = mainMenu
    }

    @objc private func resetSurface() {
        gameViewController?.resetSurface()
    }

    @objc private func captureDesktop() {
        gameViewController?.captureDesktop()
    }
}
