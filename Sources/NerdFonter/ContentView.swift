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
            } else if case .loaded(let catalog) = model.catalogState {
                // Only when search or a filter hides the selection; at launch a font is always selected.
                ContentUnavailableView {
                    Label("Nerd Fonter", systemImage: "textformat")
                } description: {
                    Text(summary(of: catalog))
                }
            }
        }
        .tint(Theme.accent)
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
                HStack(spacing: 6) {
                    // Installed fonts show their name in their own face; the rest stay in the system font.
                    if let face = model.installedFaces[font.id] {
                        Text(font.name).font(Font(face.font(size: NSFont.systemFontSize)))
                    } else {
                        Text(font.name)
                    }
                    Spacer()
                    if model.favorites.contains(font.id) {
                        Image(systemName: "star.fill").foregroundStyle(.yellow).imageScale(.small)
                    }
                    if model.isUpdateAvailable(font.id) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.tint)
                            .help("Update available")
                    } else if model.installed[font.id] != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .help("Installed")
                    }
                }
                .contextMenu {
                    Button(model.favorites.contains(font.id) ? "Remove from Favorites" : "Add to Favorites") {
                        model.toggleFavorite(font.id)
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("Show", selection: $model.filter) {
                    ForEach(AppModel.Filter.allCases) { filter in
                        Image(systemName: filter.systemImage)
                            .accessibilityLabel(filter.rawValue)
                            .help(filter.rawValue)
                            .tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }
            .overlay {
                if model.fonts.isEmpty {
                    if !model.searchText.isEmpty {
                        ContentUnavailableView.search(text: model.searchText)
                    } else {
                        model.filter.emptyState
                    }
                }
            }
        }
    }
}

extension ContentView {
    /// "72 fonts · 5 installed · 2 updates"
    private func summary(of catalog: Catalog) -> String {
        let updates = model.installed.keys.filter(model.isUpdateAvailable).count
        var parts = ["\(catalog.fonts.count) fonts", "\(model.installed.count) installed"]
        if updates > 0 { parts.append("\(updates) update\(updates == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}

extension AppModel.Filter {
    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .installed: "checkmark.circle"
        case .favorites: "star"
        case .updates: "arrow.down.circle"
        }
    }

    var emptyState: ContentUnavailableView<Label<Text, Image>, Text?, EmptyView> {
        switch self {
        case .all:
            ContentUnavailableView(
                "No Fonts", systemImage: "textformat",
                description: Text("The Nerd Fonts catalog is empty."))
        case .installed:
            ContentUnavailableView(
                "No Fonts Installed", systemImage: "checkmark.circle",
                description: Text("Fonts you install appear here."))
        case .favorites:
            ContentUnavailableView(
                "No Favorites", systemImage: "star",
                description: Text("Star a font to find it here."))
        case .updates:
            ContentUnavailableView(
                "Everything's Up to Date", systemImage: "checkmark.seal",
                description: Text("Installed fonts are on the latest Nerd Fonts release."))
        }
    }
}
