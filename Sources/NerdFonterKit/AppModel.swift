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

    public private(set) var catalogState = CatalogState.loading
    public var searchText = ""
    public var selection: FontFamily.ID?

    public private(set) var preview = PreviewState.loading(nil)
    /// Kept across fonts: most people want the same variant everywhere.
    public var variant = FontFace.Variant.mono
    private var chosenBaseName: String?
    public var previewText = PreviewSample.text
    public var previewSize = 16.0

    private let store: CatalogStore
    private let fontStore: FontStore
    /// Identifies the latest preview load so slower, older loads can't overwrite it.
    private var previewToken = UUID()

    public init(store: CatalogStore = .live, fontStore: FontStore = .live) {
        self.store = store
        self.fontStore = fontStore
    }

    // MARK: Catalog

    public var fonts: [FontFamily] {
        guard case .loaded(let catalog) = catalogState else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return catalog.fonts }
        return catalog.fonts.filter {
            $0.name.localizedStandardContains(query) || $0.patchedName.localizedStandardContains(query)
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
        } catch {
            catalogState = .failed
        }
    }

    // MARK: Preview

    public func loadPreview() async {
        guard let font = selectedFont, case .loaded(let catalog) = catalogState else { return }
        let token = UUID()
        previewToken = token
        chosenBaseName = nil
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

    /// The face to render: the chosen typeface and variant, falling back to any variant of that typeface.
    public var previewFace: FontFace? {
        let candidates = faces.filter { $0.baseName == baseName }
        return candidates.first { $0.variant == variant } ?? candidates.first
    }
}
