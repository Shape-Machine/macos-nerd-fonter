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
            // Library rows are part of the list, so fonts can never scroll underneath them.
            List(selection: $model.selection) {
                Section {
                    ForEach(AppModel.Filter.allCases) { LibraryRow(filter: $0, model: model) }
                }
                if model.fonts.isEmpty {
                    Group {
                        if !model.searchText.isEmpty {
                            ContentUnavailableView.search(text: model.searchText)
                        } else {
                            model.filter.emptyState
                        }
                    }
                    .padding(.top, 24)
                } else {
                    ForEach(model.sections) { section in
                        if let title = section.title {
                            Section(title) { rows(section.fonts) }
                        } else {
                            Section { rows(section.fonts) }
                        }
                    }
                }
            }
        }
    }

    private func rows(_ fonts: [FontFamily]) -> some View {
        ForEach(fonts) { font in
            FontRow(font: font, model: model)
                .contextMenu {
                    Button(model.favorites.contains(font.id) ? "Remove from Favorites" : "Add to Favorites") {
                        model.toggleFavorite(font.id)
                    }
                }
        }
    }
}

/// One of All / Installed / Favorites / Updates, with its count, like a mailbox in Mail.
/// Not a selectable list row (the list selects fonts); a button styled to match the sidebar.
private struct LibraryRow: View {
    let filter: AppModel.Filter
    let model: AppModel

    var body: some View {
        let isSelected = model.filter == filter
        Button { model.filter = filter } label: {
            HStack(spacing: 8) {
                Image(systemName: filter.systemImage)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                    .frame(width: 18)
                Text(filter.title)
                Spacer()
                Text("\(model.count(for: filter))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 7))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
    }
}

/// Name (in its own face when installed) over a quiet line of what matters about it.
private struct FontRow: View {
    let font: FontFamily
    let model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                if let face = model.installedFaces[font.id] {
                    Text(font.name).font(Font(face.font(size: NSFont.systemFontSize)))
                } else {
                    Text(font.name)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer()
            if model.favorites.contains(font.id) {
                Image(systemName: "star.fill").foregroundStyle(.yellow).imageScale(.small)
            }
            if model.isUpdateAvailable(font.id) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.tint)
                    .help("Update available")
            }
        }
        .padding(.vertical, 2)
    }

    /// What's worth knowing at a glance. Never just "Installed": the section header, the filter
    /// and the name drawn in its own face already say that.
    private var subtitle: String {
        if let installation = model.installed[font.id] {
            if model.isUpdateAvailable(font.id), let current = installation.nerdFontsVersion {
                return "Update · \(current) → \(model.latestVersion ?? "")"
            }
            if installation.isSystemWide { return "Installed for all users" }
        }
        return "\(font.isMonospaced ? "Mono" : "Proportional") · \(font.licenseId)"
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
    var title: String { self == .all ? "All Fonts" : rawValue }

    var systemImage: String {
        switch self {
        case .all: "textformat"
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
