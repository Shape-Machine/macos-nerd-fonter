import Testing
@testable import NerdFonterKit

@MainActor
struct AppModelTests {
    private func loadedModel() async -> AppModel {
        let model = AppModel(store: Fixtures.store(Fixtures.Server(), cacheFile: Fixtures.tempFile()))
        await model.loadCatalog()
        return model
    }

    @Test func loadsCatalog() async {
        let model = await loadedModel()
        #expect(model.fonts.count == 3)
    }

    @Test func failsWhenOfflineWithoutCache() async {
        let model = AppModel(store: Fixtures.store(Fixtures.Server(offline: true), cacheFile: Fixtures.tempFile()))
        await model.loadCatalog()
        #expect(model.catalogState == .failed)
        #expect(model.fonts.isEmpty)
    }

    @Test func searchMatchesDisplayAndPatchedNames() async {
        let model = await loadedModel()
        model.searchText = "jetbrains"
        #expect(model.fonts.map(\.id) == ["JetBrainsMono"])
        model.searchText = "sauce"
        #expect(model.fonts.map(\.id) == ["SourceCodePro"])
        model.searchText = "  "
        #expect(model.fonts.count == 3)
    }

    @Test func selectionResolvesToFont() async {
        let model = await loadedModel()
        #expect(model.selectedFont == nil)
        model.selection = "Arimo"
        #expect(model.selectedFont?.name == "Arimo")
    }

    @Test func searchHidesAndRestoresSelection() async {
        let model = await loadedModel()
        model.selection = "Arimo"
        model.searchText = "jetbrains"
        #expect(model.selectedFont == nil)
        model.searchText = ""
        #expect(model.selectedFont?.name == "Arimo")
    }
}
