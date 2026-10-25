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
        case all = "All", installed = "Installed"
        public var id: Self { self }
    }

    public enum Operation: Equatable {
        /// Download progress, or nil while connecting or unpacking.
        case installing(Double?)
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

    private let store: CatalogStore
    private let fontStore: FontStore
    private let library: FontLibrary
    /// Identifies the latest preview load so slower, older loads can't overwrite it.
    private var previewToken = UUID()
    /// Same, for scans of the Fonts folders.
    private var scanToken = UUID()

    public init(store: CatalogStore = .live, fontStore: FontStore = .live, library: FontLibrary = .live) {
        self.store = store
        self.fontStore = fontStore
        self.library = library
    }

    // MARK: Catalog

    public var fonts: [FontFamily] {
        guard case .loaded(let catalog) = catalogState else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return catalog.fonts.filter { font in
            (filter == .all || installed[font.id] != nil)
                && (query.isEmpty || font.name.localizedStandardContains(query)
                    || font.patchedName.localizedStandardContains(query))
        }
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

    public func install(_ font: FontFamily) async {
        guard case .loaded(let catalog) = catalogState, operations[font.id] == nil else { return }
        operations[font.id] = .installing(nil)
        defer { operations[font.id] = nil }
        do {
            let archive = try await fontStore.archive(for: font, release: catalog.release) { progress in
                Task { @MainActor [weak self] in
                    guard let self, case .installing = self.operations[font.id] else { return }
                    self.operations[font.id] = .installing(progress)
                }
            }
            _ = try await library.install(archive: archive)
        } catch {
            failure = "Couldn't install \(font.name). \(error.localizedDescription)"
        }
        await refreshInstalled()
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
