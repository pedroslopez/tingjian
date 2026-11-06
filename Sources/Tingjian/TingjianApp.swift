import AppKit
import SwiftUI

@main
struct TingjianApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: delegate.model, overlay: delegate.overlay)
        } label: {
            MenuBarLabel(model: delegate.model, animator: delegate.iconAnimator)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let iconAnimator = IconAnimator()
    private(set) lazy var overlay = OverlayController(model: model)
    private var controlsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.applyDockPolicy()
        _ = overlay
        model.installHotKey()
        iconAnimator.bind(to: model)

        // Scriptable toggle (Shortcuts, Raycast, …):
        //   notifyutil-style: post "com.pedroslopez.tingjian.toggle" on the distributed center.
        DistributedNotificationCenter.default().addObserver(
            forName: .init("com.pedroslopez.tingjian.toggle"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.toggle() }
        }
        if CommandLine.arguments.contains("--start") {
            model.toggle()
        }
    }

    // MARK: Dock

    /// Clicking the Dock icon opens the controls in a regular window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showControlsWindow()
        return false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let toggle = NSMenuItem(title: model.isListening || model.isBusy ? "Stop Listening" : "Start Listening",
                                action: #selector(toggleListening), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        let controls = NSMenuItem(title: "Show Controls", action: #selector(showControlsFromMenu), keyEquivalent: "")
        controls.target = self
        menu.addItem(controls)
        return menu
    }

    @objc private func toggleListening() { model.toggle() }
    @objc private func showControlsFromMenu() { showControlsWindow() }

    func showControlsWindow() {
        if controlsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.title = "tingjian"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: MenuView(model: model, overlay: overlay).padding(.top, 14))
            host.sizingOptions = [.preferredContentSize]
            window.contentView = host
            window.setFrameAutosaveName("ControlsWindow")
            if !window.setFrameUsingName("ControlsWindow") { window.center() }
            controlsWindow = window
        }
        NSApp.activate()
        controlsWindow?.makeKeyAndOrderFront(nil)
    }
}

/// Drives the menu bar icon's animation frames while listening.
@MainActor
@Observable
final class IconAnimator {
    private(set) var phase: Double = 0
    private var task: Task<Void, Never>?

    func bind(to model: AppModel) {
        withObservationTracking {
            _ = model.isListening
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update(listening: model.isListening)
                self?.bind(to: model)
            }
        }
        update(listening: model.isListening)
    }

    private func update(listening: Bool) {
        if listening, task == nil {
            task = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(90))
                    self?.phase += 0.09
                }
            }
        } else if !listening {
            task?.cancel()
            task = nil
        }
    }
}

struct MenuBarLabel: View {
    let model: AppModel
    let animator: IconAnimator

    var body: some View {
        Image(nsImage: MenuBarIcon.image(active: model.isListening, level: model.level, phase: animator.phase))
            .accessibilityLabel(model.isListening ? "tingjian, listening" : "tingjian")
    }
}
