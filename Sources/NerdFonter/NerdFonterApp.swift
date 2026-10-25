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
    }
}
