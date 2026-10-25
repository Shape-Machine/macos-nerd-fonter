import NerdFonterKit
import SwiftUI

@main
struct NerdFonterApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Nerd Fonter", id: "main") {
            ContentView(model: model)
        }
        .defaultSize(width: 960, height: 640)
        .commands {
            CommandMenu("Font") { FontCommands(model: model) }
            CommandGroup(before: .sidebar) { FilterCommands(model: model) }
        }
    }
}

/// Actions on the selected font. Uninstall has no shortcut: ⌘⌫ would fire while editing the preview text.
private struct FontCommands: View {
    let model: AppModel

    var body: some View {
        let font = model.selectedFont
        let isBusy = font.map { model.operations[$0.id] != nil } ?? true
        let installation = font.flatMap { model.installed[$0.id] }

        if let font, installation != nil, model.isUpdateAvailable(font.id) {
            Button("Update") { Task { await model.update(font) } }
                .keyboardShortcut(.return)
                .disabled(isBusy)
        } else {
            Button("Install") { if let font { Task { await model.install(font) } } }
                .keyboardShortcut(.return)
                .disabled(font == nil || installation != nil || isBusy)
        }
        Button("Uninstall") { if let font { Task { await model.uninstall(font) } } }
            .disabled(installation == nil || installation?.isSystemWide == true || isBusy)

        Divider()

        Button(font.map { model.favorites.contains($0.id) } == true ? "Remove from Favorites" : "Add to Favorites") {
            if let font { model.toggleFavorite(font.id) }
        }
        .keyboardShortcut("d")
        .disabled(font == nil)

        Divider()

        Button("Clear Download Cache") { Task { await model.clearCache() } }
            .disabled(!model.canClearCache)
    }
}

private struct FilterCommands: View {
    let model: AppModel

    var body: some View {
        ForEach(Array(AppModel.Filter.allCases.enumerated()), id: \.element) { index, filter in
            Button("Show \(filter.rawValue)") { model.filter = filter }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
        }
        Divider()
    }
}
