import AppKit
import MacKitLifecycle
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    var present: (() -> Void)?
    private weak var window: NSWindow?
    private let activationSession = AccessoryActivationSession()
    private var observers: [NSObjectProtocol] = []

    func show() {
        present?()
        NSApp.activate()
    }

    func close() { window?.performClose(nil) }

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        self.window = window
        window.title = String(localized: "settings.title")
        window.setFrameAutosaveName("Mirror.Settings")
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated {
                    Self.shared.activationSession.beginIfAccessory()
                    Self.shared.clampToVisibleScreen()
                }
            },
            center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { Self.shared.clampToVisibleScreen() }
            },
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { Self.shared.activationSession.endIfNeeded() }
            }
        ]
        if window.isKeyWindow { activationSession.beginIfAccessory() }
        DispatchQueue.main.async { self.clampToVisibleScreen() }
    }

    private func clampToVisibleScreen() {
        guard let window, let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var frame = window.frame
        frame.origin.x = min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - frame.width))
        frame.origin.y = min(max(frame.minY, visible.minY), max(visible.minY, visible.maxY - frame.height))
        if frame.origin != window.frame.origin { window.setFrame(frame, display: true) }
    }
}

struct SettingsWindowObserver: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowView { WindowView() }
    func updateNSView(_ nsView: WindowView, context: Context) {}

    final class WindowView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { SettingsWindowController.shared.attach(window) }
        }
    }
}

struct SettingsPresenterCommands: Commands {
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Color.clear.frame(width: 0, height: 0)
                .onAppear { SettingsWindowController.shared.present = { openSettings() } }
        }
    }
}
