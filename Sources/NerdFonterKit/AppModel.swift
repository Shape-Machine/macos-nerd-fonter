import Foundation
import Observation

/// Root UI state. Views stay thin; behaviour lives here so it can be tested.
@MainActor
@Observable
public final class AppModel {
    public enum CatalogState: Equatable {
        case loading
        case loaded(Catalog)
        case failed
    }

    public enum PreviewState: Equatable {
        /// Download progress, or nil before any bytes arrive (or when reading from cache).
        case loading(Double?)
        case loaded([FontFace])
        case failed
    }

    public enum Filter: String, CaseIterable, Identifiable {
        case all = "All", installed = "Installed", favorites = "Favorites", updates = "Updates"
        public var id: Self { self }
    }

    public enum Operation: Equatable {
        /// Download progress, or nil while connecting or unpacking.
        case installing(Double?)
        case updating(Double?)
        case uninstalling
    }

    public private(set) var catalogState = CatalogState.loading
    public var searchText = ""
    public var filter = Filter.all
    public var selection: FontFamily.ID?

    public private(set) var installed: [FontFamily.ID: Installation] = [:]
    public private(set) var operations: [FontFamily.ID: Operation] = [:]
    /// Message for the most recent failed install or uninstall.
    public var failure: String?

    public private(set) var preview = PreviewState.loading(nil)
    /// Kept across fonts: most people want the same variant everywhere.
    public var variant = FontFace.Variant.mono
    private var chosenBaseName: String?
    public var previewText = PreviewSample.text
    public var previewSize = 16.0

    public private(set) var favorites: Set<FontFamily.ID>

    private let store: CatalogStore
    private let fontStore: FontStore
    private let library: FontLibrary
    private let defaults: UserDefaults
    private static let favoritesKey = "favorites"
    /// Identifies the latest preview load so slower, older loads can't overwrite it.
    private var previewToken = UUID()
    /// Same, for scans of the Fonts folders.
    private var scanToken = UUID()

    public init(
        store: CatalogStore = .live, fontStore: FontStore = .live, library: FontLibrary = .live,
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.fontStore = fontStore
        self.library = library
        self.defaults = defaults
        favorites = Set(defaults.stringArray(forKey: Self.favoritesKey) ?? [])
    }

    // MARK: Catalog

    public var fonts: [FontFamily] {
        guard case .loaded(let catalog) = catalogState else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return catalog.fonts.filter { font in
            let inFilter = switch filter {
            case .all: true
            case .installed: installed[font.id] != nil
            case .favorites: favorites.contains(font.id)
            case .updates: isUpdateAvailable(font.id)
            }
            return inFilter
                && (query.isEmpty || font.name.localizedStandardContains(query)
                    || font.patchedName.localizedStandardContains(query))
        }
    }

    // MARK: Favorites

    public func toggleFavorite(_ id: FontFamily.ID) {
        if favorites.remove(id) == nil { favorites.insert(id) }
        defaults.set(favorites.sorted(), forKey: Self.favoritesKey)
    }

    /// Only resolves while the selection is visible, so search never leaves a hidden font on screen.
    /// The selection itself is kept, so clearing the search brings it back.
    public var selectedFont: FontFamily? {
        fonts.first { $0.id == selection }
    }

    public func loadCatalog() async {
        catalogState = .loading
        do {
            catalogState = .loaded(try await store.load())
            await refreshInstalled()
        } catch {
            catalogState = .failed
        }
    }

    // MARK: Install

    /// Re-reads the Fonts folders. Cheap enough to run whenever the app becomes active.
    public func refreshInstalled() async {
        guard case .loaded(let catalog) = catalogState else { return }
        let token = UUID()
        scanToken = token
        let result = await library.scan(catalog: catalog.fonts)
        // A newer scan started meanwhile; its snapshot is fresher than ours.
        guard scanToken == token else { return }
        installed = result
    }

    /// Release tag without the "v", e.g. "3.5.1".
    public var latestVersion: String? {
        guard case .loaded(let catalog) = catalogState else { return nil }
        return String(catalog.release.trimmingPrefix("v"))
    }

    /// True when the family was patched with an older Nerd Fonts release and we're allowed to replace it.
    /// Unknown versions (e.g. third-party "NF" builds) are left alone: replacing them would change family names.
    public func isUpdateAvailable(_ id: FontFamily.ID) -> Bool {
        guard let installation = installed[id], !installation.isSystemWide,
              let current = installation.nerdFontsVersion, let latest = latestVersion
        else { return false }
        return current.compare(latest, options: .numeric) == .orderedAscending
    }

    public func install(_ font: FontFamily) async {
        await installLatest(font, replacing: nil)
    }

    public func update(_ font: FontFamily) async {
        guard let old = installed[font.id], isUpdateAvailable(font.id) else { return }
        await installLatest(font, replacing: old)
    }

    /// Installs the latest release; for an update, then trashes old files the new release didn't replace.
    private func installLatest(_ font: FontFamily, replacing old: Installation?) async {
        guard case .loaded(let catalog) = catalogState, operations[font.id] == nil else { return }
        let isUpdate = old != nil
        operations[font.id] = isUpdate ? .updating(nil) : .installing(nil)
        defer { operations[font.id] = nil }
        do {
            let archive = try await fontStore.archive(for: font, release: catalog.release) { progress in
                Task { @MainActor [weak self] in
                    // Only while this install or update is still running, never over a later operation.
                    switch self?.operations[font.id] {
                    case .installing where !isUpdate: self?.operations[font.id] = .installing(progress)
                    case .updating where isUpdate: self?.operations[font.id] = .updating(progress)
                    default: break
                    }
                }
            }
            let added = Set(try await library.install(archive: archive).map { $0.resolvingSymlinksInPath() })
            if let old {
                let leftovers = old.files.filter { !added.contains($0.resolvingSymlinksInPath()) }
                try await library.uninstall(Installation(files: leftovers, isSystemWide: false))
            }
        } catch {
            failure = "Couldn't \(isUpdate ? "update" : "install") \(font.name). \(error.localizedDescription)"
        }
        await refreshInstalled()
        // The preview may have been reading files we just replaced.
        if isUpdate, selectedFont?.id == font.id { await loadPreview() }
    }

    public func uninstall(_ font: FontFamily) async {
        guard let installation = installed[font.id], operations[font.id] == nil else { return }
        operations[font.id] = .uninstalling
        defer { operations[font.id] = nil }
        do {
            try await library.uninstall(installation)
        } catch {
            failure = "Couldn't uninstall \(font.name). \(error.localizedDescription)"
        }
        await refreshInstalled()
        // The preview may have been reading the files we just trashed.
        if selectedFont?.id == font.id { await loadPreview() }
    }

    // MARK: Preview

    public func loadPreview() async {
        guard let font = selectedFont, case .loaded(let catalog) = catalogState else { return }
        let token = UUID()
        previewToken = token
        chosenBaseName = nil
        // Installed families preview from their own files, no download needed. Files that don't
        // follow the release naming (e.g. pre-3.0 installs) fall through to the download.
        if let installation = installed[font.id] {
            let faces = FontStore.faces(choosingFrom: installation.files)
            if !faces.isEmpty {
                preview = .loaded(faces)
                return
            }
        }
        preview = .loading(nil)
        do {
            let faces = try await fontStore.previewFaces(for: font, release: catalog.release) { progress in
                Task { @MainActor [weak self] in
                    guard let self, self.previewToken == token, case .loading = self.preview else { return }
                    self.preview = .loading(progress)
                }
            }
            guard previewToken == token else { return }
            preview = faces.isEmpty ? .failed : .loaded(faces)
        } catch {
            guard previewToken == token else { return }
            preview = .failed
        }
    }

    private var faces: [FontFace] {
        guard case .loaded(let faces) = preview else { return [] }
        return faces
    }

    /// Typefaces in the family, e.g. ["MesloLGL", "MesloLGM", …]. The family's main one comes first.
    public var baseNames: [String] {
        let main = selectedFont?.patchedName
        return Set(faces.map(\.baseName)).sorted { lhs, rhs in
            if lhs == main || rhs == main { return lhs == main }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    public var baseName: String {
        get { chosenBaseName ?? baseNames.first ?? "" }
        set { chosenBaseName = newValue }
    }

    public var variants: [FontFace.Variant] {
        let available = Set(faces.filter { $0.baseName == baseName }.map(\.variant))
        return FontFace.Variant.allCases.filter(available.contains)
    }

    /// The variant actually on screen, for the picker. Setting it also updates the remembered variant.
    public var shownVariant: FontFace.Variant {
        get { previewFace?.variant ?? variant }
        set { variant = newValue }
    }

    /// The face to render: the chosen typeface and variant, falling back to any variant of that typeface.
    public var previewFace: FontFace? {
        let candidates = faces.filter { $0.baseName == baseName }
        return candidates.first { $0.variant == variant } ?? candidates.first
    }
}
