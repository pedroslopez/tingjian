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
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = overlay
        hotKey = HotKey { [weak self] in
            Task { @MainActor in self?.model.toggle() }
        }
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
