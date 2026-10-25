import NerdFonterKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if let font = model.selectedFont {
                FontDetailView(font: font, model: model)
                    .task(id: font.id) { await model.loadPreview() }
            } else {
                ContentUnavailableView("No Font Selected", systemImage: "textformat")
            }
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search fonts")
        .task { await model.loadCatalog() }
    }

    @ViewBuilder private var sidebar: some View {
        switch model.catalogState {
        case .loading:
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            ContentUnavailableView {
                Label("Couldn't Load Fonts", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Check your connection and try again.")
            } actions: {
                Button("Try Again") { Task { await model.loadCatalog() } }
            }
        case .loaded:
            List(model.fonts, selection: $model.selection) { font in
                Text(font.name)
            }
            .overlay {
                if model.fonts.isEmpty { ContentUnavailableView.search(text: model.searchText) }
            }
        }
    }
}
