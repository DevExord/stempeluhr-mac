// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import AppKit

struct StempeluhrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only agent: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)
    }
}

/// The status-bar label: a stopwatch, plus the ticking `H:MM` while running.
struct MenuBarLabel: View {
    @ObservedObject var store: AppStore

    var body: some View {
        if store.isRunning, let e = store.elapsed {
            Image(systemName: "stopwatch.fill")
            Text(Fmt.hm(e))
        } else {
            Image(systemName: "stopwatch")
        }
    }
}
