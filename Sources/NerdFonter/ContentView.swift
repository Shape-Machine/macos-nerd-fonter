import NerdFonterKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List {}
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            ContentUnavailableView("No Font Selected", systemImage: "textformat")
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search fonts")
    }
}
