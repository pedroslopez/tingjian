import AppKit
import SwiftUI

/// Borderless, non-activating, click-through subtitle panel that floats above
/// everything on every Space (including full-screen apps).
final class OverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 280),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Mouse events only reach us while the drag modifier is held; any click drags.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            performDrag(with: event)
        } else {
            super.sendEvent(event)
        }
    }
}

/// Owns the overlay panel: visibility, drag-with-⌘, and remembered position.
@MainActor
final class OverlayController {
    /// Hold this to make the overlay draggable.
    static let dragModifier: NSEvent.ModifierFlags = .command

    private let panel = OverlayPanel()
    private let model: AppModel
    private let state = OverlayState()
    private var modifierTimer: Timer?
    private var moveObserver: NSObjectProtocol?
    private var hideWorkItem: DispatchWorkItem?

    private static let originKey = "overlayOrigin"

    init(model: AppModel) {
        self.model = model
        let host = NSHostingView(rootView: OverlayView(model: model, state: state))
        host.sizingOptions = []
        panel.contentView = host
        panel.alphaValue = 0

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveOrigin() }
        }
        observeListening()
    }

    // MARK: Visibility

    private func observeListening() {
        withObservationTracking {
            _ = model.status
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.updateVisibility()
                self.observeListening()
            }
        }
    }

    private func updateVisibility() {
        switch model.status {
        case .listening, .preparing: show()
        case .idle, .failed: hide()
        }
    }

    private func show() {
        hideWorkItem?.cancel()
        if !panel.isVisible {
            placePanel()
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 1
        }
        startModifierPolling()
    }

    private func hide() {
        stopModifierPolling()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            panel.animator().alphaValue = 0
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.panel.alphaValue == 0 else { return }
            self.panel.orderOut(nil)
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    // MARK: Drag with modifier

    /// `NSEvent.modifierFlags` is readable without Accessibility permission,
    /// unlike a global key-event monitor, so poll it while visible.
    private func startModifierPolling() {
        guard modifierTimer == nil else { return }
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollModifiers() }
        }
        RunLoop.main.add(timer, forMode: .common)
        modifierTimer = timer
    }

    private func stopModifierPolling() {
        modifierTimer?.invalidate()
        modifierTimer = nil
        setInteractive(false)
    }

    private func pollModifiers() {
        let held = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(Self.dragModifier)
        let dragging = NSEvent.pressedMouseButtons & 1 != 0 && !panel.ignoresMouseEvents
        let hovering = panel.frame.contains(NSEvent.mouseLocation)
        setInteractive((held && hovering) || dragging)
    }

    private func setInteractive(_ interactive: Bool) {
        if panel.ignoresMouseEvents == interactive { panel.ignoresMouseEvents = !interactive }
        if state.isInteractive != interactive {
            withAnimation(.easeOut(duration: 0.15)) { state.isInteractive = interactive }
        }
    }

    // MARK: Position

    private func placePanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let width = min(1000, screen.visibleFrame.width * 0.8)
        let size = NSSize(width: width, height: 300)
        if let saved = UserDefaults.standard.string(forKey: Self.originKey) {
            let origin = NSPointFromString(saved)
            let frame = NSRect(origin: origin, size: size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame.insetBy(dx: size.width / 3, dy: size.height / 3)) }) {
                panel.setFrame(frame, display: false)
                return
            }
        }
        let visible = screen.visibleFrame
        panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.minY + 40, width: size.width, height: size.height), display: false)
    }

    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: Self.originKey)
        placePanel()
    }

    private func saveOrigin() {
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: Self.originKey)
    }
}

/// View-only state the controller drives.
@MainActor
@Observable
final class OverlayState {
    var isInteractive = false
}
