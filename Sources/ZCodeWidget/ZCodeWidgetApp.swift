import AppKit

@main
struct ZCodeWidgetApp {
    static func main() {
        let app = NSApplication.shared
        // Use .regular so we can have a status bar item and stay alive
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: FloatingPanelController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Register status bar item FIRST so it survives even if window is closed
        setupStatusItem()

        // 2. Create and show the panel
        panelController = FloatingPanelController()
        panelController?.showWindow(nil)
        panelController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when window closes - keep the status bar item alive
        return false
    }

    // MARK: - Status Bar Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            // Use a distinctive text "Z" so it's clearly our widget, not Gemini
            button.title = " Z"
            button.font = NSFont.systemFont(ofSize: 13, weight: .bold)
            button.imagePosition = .imageOnly
            button.image = createStatusBarIcon()
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func createStatusBarIcon() -> NSImage? {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        // Draw a "Z" letter
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .heavy),
            .foregroundColor: NSColor.labelColor
        ]
        let str = "Z" as NSString
        let strSize = str.size(withAttributes: attrs)
        str.draw(at: NSPoint(x: (size.width - strSize.width) / 2,
                             y: (size.height - strSize.height) / 2),
                 withAttributes: attrs)
        return image
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func togglePanel() {
        guard let window = panelController?.window else { return }
        if window.isVisible && window.isKeyWindow {
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show ZCode Widget", action: #selector(openWidget), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Hide ZCode Widget", action: #selector(hideWidget), keyEquivalent: "h"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit ZCode Widget", action: #selector(quitApp), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openWidget() {
        panelController?.showWindow(nil)
        panelController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func hideWidget() {
        panelController?.window?.orderOut(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
