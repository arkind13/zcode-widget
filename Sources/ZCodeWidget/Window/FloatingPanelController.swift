import AppKit
import SwiftUI

/// Borderless windows refuse key-window status by default, which silently
/// blocks all keyboard input (TextFields never receive focus). Overriding
/// canBecomeKey fixes that; .nonactivatingPanel lets the panel take key
/// status without activating the app, so the user's current app stays frontmost.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

class FloatingPanelController: NSWindowController {
    convenience init() {
        let contentView = ContentView()
        let hostingController = NSHostingController(rootView: contentView)

        // KeyablePanel (not plain NSWindow) so text fields accept typing;
        // still borderless and movable by dragging the background.
        let window = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 520),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = "ZCode Widget"
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96)
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.hidesOnDeactivate = false

        // The window is closed (X) instead of terminated. App stays alive.
        window.isReleasedWhenClosed = false

        self.init(window: window)
        configureWindow()
    }

    private func configureWindow() {
        guard let win = window else { return }
        // Center on screen on first launch
        win.center()
    }
}
