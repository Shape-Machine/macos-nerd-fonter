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

    public private(set) var catalogState = CatalogState.loading
    public var searchText = ""
    public var selection: FontFamily.ID?

    private let store: CatalogStore

    public init(store: CatalogStore = .live) {
        self.store = store
    }

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
}
