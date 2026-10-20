import AppKit
import SwiftUI

/// Shared constants used across the app.
enum AppLinks {
    static func openDonation() {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
    }
}

/// App entry point: a single main window, Settings, and menu-bar commands.
@main
struct BatchNameForgeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("BatchNameForge", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 520)
        }
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView()
        }
    }
}

/// File-menu commands (Open, Clear, Presets) and the Help-menu support link.
struct AppCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Files…") { model.openPanel() }
                .keyboardShortcut("o")
            Button("Clear List") { model.clear() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(model.items.isEmpty)
            Divider()
            Menu("Presets") {
                Button("Save Rules as Preset…") { model.savePreset() }
                    .disabled(model.rules.isEmpty)
                if !model.presets.isEmpty {
                    Divider()
                    ForEach(model.presets) { preset in
                        Button("Load “\(preset.name)”") { model.load(preset) }
                    }
                    Divider()
                    Menu("Delete Preset") {
                        ForEach(model.presets) { preset in
                            Button(preset.name) { model.delete(preset) }
                        }
                    }
                }
            }
        }
        CommandGroup(after: .help) {
            Button("Support / Donate ❤️") { AppLinks.openDonation() }
        }
    }
}
