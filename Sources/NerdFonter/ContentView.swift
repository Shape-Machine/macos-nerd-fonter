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
                FontDetailView(font: font)
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

private struct FontDetailView: View {
    let font: FontFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(font.name).font(.largeTitle.weight(.semibold))
            Text(font.description).foregroundStyle(.secondary)
            Text("\(font.licenseId) · v\(font.version)")
                .font(.callout).foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .navigationTitle(font.name)
    }
}
