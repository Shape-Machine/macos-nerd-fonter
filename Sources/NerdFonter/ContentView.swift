import AppKit
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
        // Pick up fonts installed or removed elsewhere (Homebrew, Font Book) while we were in the background.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refreshInstalled() }
        }
        .alert(
            model.failure ?? "", isPresented: Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } })
        ) {}
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
                HStack {
                    Text(font.name)
                    Spacer()
                    if model.installed[font.id] != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .help("Installed")
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("Show", selection: $model.filter) {
                    ForEach(AppModel.Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }
            .overlay {
                if model.fonts.isEmpty {
                    if !model.searchText.isEmpty {
                        ContentUnavailableView.search(text: model.searchText)
                    } else {
                        ContentUnavailableView(
                            "No Fonts Installed", systemImage: "textformat",
                            description: Text("Fonts you install appear here."))
                    }
                }
            }
        }
    }
}
