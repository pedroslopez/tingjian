import SwiftUI

@main
struct TingjianApp: App {
    var body: some Scene {
        MenuBarExtra("tingjian", systemImage: "waveform") {
            Button("Quit tingjian") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
