import Foundation
import Testing
@testable import NerdFonterKit

@MainActor
struct AppModelTests {
    private func loadedModel(library: FontLibrary = Fixtures.library()) async -> AppModel {
        let model = Fixtures.model(library: library)
        await model.loadCatalog()
        return model
    }

    @Test func loadsCatalog() async {
        let model = await loadedModel()
        #expect(model.fonts.count == 3)
    }

    @Test func failsWhenOfflineWithoutCache() async {
        let model = AppModel(
            store: Fixtures.store(Fixtures.Server(offline: true), cacheFile: Fixtures.tempFile()),
            library: Fixtures.library())
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

    @Test func previewDefaultsToMainTypefaceAndKeepsVariant() async throws {
        let archive = try FontStoreTests.makeArchive([
            "JetBrainsMonoNerdFont-Regular.ttf", "JetBrainsMonoNerdFontMono-Regular.ttf",
            "JetBrainsMonoNLNerdFont-Regular.ttf",
        ])
        let model = Fixtures.model(fontStore: FontStoreTests.store(serving: archive, counter: .init()))
        await model.loadCatalog()
        model.selection = "JetBrainsMono"
        await model.loadPreview()

        #expect(model.baseNames == ["JetBrainsMono", "JetBrainsMonoNL"])
        #expect(model.variants == [.standard, .mono])
        #expect(model.previewFace?.url.lastPathComponent == "JetBrainsMonoNerdFontMono-Regular.ttf")

        // NL has no Mono: fall back to what exists without changing the remembered variant.
        model.baseName = "JetBrainsMonoNL"
        #expect(model.previewFace?.url.lastPathComponent == "JetBrainsMonoNLNerdFont-Regular.ttf")
        #expect(model.shownVariant == .standard)
        #expect(model.variant == .mono)
    }

    @Test func previewFailsWhenDownloadFails() async {
        let model = await loadedModel()
        model.selection = "Arimo"
        await model.loadPreview()
        #expect(model.preview == .failed)
    }

    @Test func searchHidesAndRestoresSelection() async {
        let model = await loadedModel()
        model.selection = "Arimo"
        model.searchText = "jetbrains"
        #expect(model.selectedFont == nil)
        model.searchText = ""
        #expect(model.selectedFont?.name == "Arimo")
    }

    @Test func detectsInstalledFontsAndFilters() async throws {
        let library = Fixtures.library()
        try Fixtures.touch(library.userFonts, ["ArimoNerdFont-Regular.ttf"])
        let model = await loadedModel(library: library)

        #expect(model.installed.keys.sorted() == ["Arimo"])
        model.filter = .installed
        #expect(model.fonts.map(\.id) == ["Arimo"])
    }

    @Test func installsAndUninstalls() async throws {
        let archive = try FontStoreTests.makeArchive(["ArimoNerdFont-Regular.ttf", "ArimoNerdFontMono-Regular.ttf"])
        let library = Fixtures.library()
        let model = Fixtures.model(fontStore: FontStoreTests.store(serving: archive, counter: .init()), library: library)
        await model.loadCatalog()
        let arimo = try #require(model.fonts.first { $0.id == "Arimo" })

        await model.install(arimo)
        #expect(model.installed["Arimo"]?.files.count == 2)
        #expect(model.operations.isEmpty)
        #expect(model.failure == nil)

        await model.uninstall(arimo)
        #expect(model.installed["Arimo"] == nil)
        #expect(FontLibrary.fontFiles(in: library.userFonts).isEmpty)
    }

    @Test func reportsInstallFailure() async throws {
        let model = await loadedModel()
        let arimo = try #require(model.fonts.first { $0.id == "Arimo" })
        await model.install(arimo)
        #expect(model.failure?.contains("Arimo") == true)
        #expect(model.operations.isEmpty)
    }
}
