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
            library: Fixtures.library(), defaults: Fixtures.defaults())
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
        model.selection = nil
        #expect(model.selectedFont == nil)
        model.selection = "SourceCodePro"
        #expect(model.selectedFont?.name == "Source Code Pro")
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

    @Test func previewsInstalledFontWithoutDownloading() async throws {
        let library = Fixtures.library()
        let font = URL(filePath: "/System/Library/Fonts/Supplemental/Andale Mono.ttf")
        try FileManager.default.createDirectory(at: library.userFonts, withIntermediateDirectories: true)
        for name in ["ArimoNerdFont-Regular.ttf", "ArimoNerdFont-Bold.ttf", "ArimoNerdFontMono-Regular.ttf"] {
            try FileManager.default.copyItem(at: font, to: library.userFonts.appending(path: name))
        }
        let model = await loadedModel(library: library)  // its font store is offline
        model.selection = "Arimo"
        await model.loadPreview()

        guard case .loaded(let faces) = model.preview else {
            Issue.record("expected a loaded preview, got \(model.preview)")
            return
        }
        #expect(faces.map(\.url.lastPathComponent).sorted() == ["ArimoNerdFont-Regular.ttf", "ArimoNerdFontMono-Regular.ttf"])
    }

    @Test func installedFamilyNameOnlyForInstalledFaces() async throws {
        let library = Fixtures.library()
        let font = URL(filePath: "/System/Library/Fonts/Supplemental/Andale Mono.ttf")
        try FileManager.default.createDirectory(at: library.userFonts, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: font, to: library.userFonts.appending(path: "ArimoNerdFont-Regular.ttf"))
        // Installed too, but its (empty) file can't be previewed, so its preview is downloaded.
        try Fixtures.touch(library.userFonts, ["JetBrainsMonoNerdFont-Regular.ttf"])
        let archive = try FontStoreTests.makeArchive(["JetBrainsMonoNerdFont-Regular.ttf"])
        let model = Fixtures.model(fontStore: FontStoreTests.store(serving: archive, counter: .init()), library: library)
        await model.loadCatalog()

        model.selection = "Arimo"
        await model.loadPreview()
        #expect(model.installedFamilyName == "Andale Mono")

        // Switched, but Arimo's preview is still on screen until the new one loads.
        model.selection = "JetBrainsMono"
        #expect(model.installedFamilyName == nil)

        // Downloaded preview: its name isn't necessarily the installed one.
        await model.loadPreview()
        #expect(model.previewFace != nil)
        #expect(model.installedFamilyName == nil)
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

    // MARK: Updates

    @Test func offersUpdateForOlderReleaseAndReplacesLeftovers() async throws {
        let library = Fixtures.library()
        try Fixtures.touch(library.userFonts, ["ArimoNerdFont-Regular@3.3.0.ttf", "ArimoNerdFont-Italic@3.3.0.ttf"])
        let archive = try FontStoreTests.makeArchive(["ArimoNerdFont-Regular.ttf", "ArimoNerdFontMono-Regular.ttf"])
        let model = Fixtures.model(fontStore: FontStoreTests.store(serving: archive, counter: .init()), library: library)
        await model.loadCatalog()
        let arimo = try #require(model.fonts.first { $0.id == "Arimo" })

        #expect(model.isUpdateAvailable("Arimo"))
        model.filter = .updates
        #expect(model.fonts.map(\.id) == ["Arimo"])

        await model.update(arimo)
        #expect(model.failure == nil)
        #expect(!model.isUpdateAvailable("Arimo"))
        #expect(model.installed["Arimo"]?.nerdFontsVersion == "3.5.1")
        let files = try FileManager.default.contentsOfDirectory(atPath: library.userFonts.path).sorted()
        #expect(files == ["ArimoNerdFont-Regular.ttf", "ArimoNerdFontMono-Regular.ttf"])
    }

    @Test func noUpdateForCurrentOrSystemWideFonts() async throws {
        let library = Fixtures.library()
        try Fixtures.touch(library.userFonts, ["ArimoNerdFont-Regular.ttf"])
        try Fixtures.touch(library.systemFonts, ["JetBrainsMonoNerdFont-Regular@3.3.0.ttf"])
        let model = await loadedModel(library: library)
        #expect(!model.isUpdateAvailable("Arimo"))
        #expect(!model.isUpdateAvailable("JetBrainsMono"))
        #expect(model.installed["JetBrainsMono"]?.isSystemWide == true)
    }

    // MARK: Favorites

    @Test func favoritesFilterAndPersist() async {
        let defaults = Fixtures.defaults()
        let model = Fixtures.model(defaults: defaults)
        await model.loadCatalog()
        model.toggleFavorite("Arimo")
        model.toggleFavorite("SourceCodePro")
        model.toggleFavorite("SourceCodePro")
        model.filter = .favorites
        #expect(model.fonts.map(\.id) == ["Arimo"])

        let reopened = Fixtures.model(defaults: defaults)
        #expect(reopened.favorites == ["Arimo"])
    }

    // MARK: Selection

    @Test func selectsAFontAtLaunch() async throws {
        // Nothing known: the first font.
        #expect(await loadedModel().selection == "Arimo")

        // An installed font beats the first one; a favorite beats both.
        let library = Fixtures.library()
        try Fixtures.touch(library.userFonts, ["SauceCodeProNerdFont-Regular.ttf"])
        let defaults = Fixtures.defaults()
        let model = Fixtures.model(library: library, defaults: defaults)
        await model.loadCatalog()
        #expect(model.selection == "SourceCodePro")

        model.toggleFavorite("JetBrainsMono")
        let withFavorite = Fixtures.model(library: library, defaults: Fixtures.defaults())
        withFavorite.toggleFavorite("JetBrainsMono")
        await withFavorite.loadCatalog()
        #expect(withFavorite.selection == "JetBrainsMono")
    }

    @Test func remembersSelectionAcrossLaunches() async {
        let defaults = Fixtures.defaults()
        let first = Fixtures.model(defaults: defaults)
        await first.loadCatalog()
        first.selection = "SourceCodePro"

        let reopened = Fixtures.model(defaults: defaults)
        await reopened.loadCatalog()
        #expect(reopened.selection == "SourceCodePro")
    }

    @Test func installedFacesPreferTheMainTypeface() async throws {
        let library = Fixtures.library()
        let font = URL(filePath: "/System/Library/Fonts/Supplemental/Andale Mono.ttf")
        try FileManager.default.createDirectory(at: library.userFonts, withIntermediateDirectories: true)
        for name in ["JetBrainsMonoNLNerdFont-Regular.ttf", "JetBrainsMonoNerdFont-Regular.ttf", "JetBrainsMonoNerdFontMono-Regular.ttf"] {
            try FileManager.default.copyItem(at: font, to: library.userFonts.appending(path: name))
        }
        let model = await loadedModel(library: library)
        #expect(model.installedFaces["JetBrainsMono"]?.url.lastPathComponent == "JetBrainsMonoNerdFont-Regular.ttf")
        #expect(model.installedFaces["Arimo"] == nil)
    }

    @Test func selectedPreviewFaceWaitsForTheNewFont() async throws {
        let library = Fixtures.library()
        let font = URL(filePath: "/System/Library/Fonts/Supplemental/Andale Mono.ttf")
        try FileManager.default.createDirectory(at: library.userFonts, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: font, to: library.userFonts.appending(path: "ArimoNerdFont-Regular.ttf"))
        let model = await loadedModel(library: library)
        model.selection = "Arimo"
        await model.loadPreview()
        #expect(model.selectedPreviewFace != nil)
        model.selection = "SourceCodePro"
        #expect(model.selectedPreviewFace == nil)
    }

    // MARK: Cache

    @Test func clearCacheWaitsForPreviewsOfFontsNoLongerSelected() async throws {
        let gate = Gate()
        let archive = try FontStoreTests.makeArchive(["ArimoNerdFont-Regular.ttf"])
        let slow = FontStore(root: Fixtures.tempFile()) { _, _ in
            await gate.wait()
            let copy = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.copyItem(at: archive, to: copy)
            return copy
        }
        let model = Fixtures.model(fontStore: slow)
        await model.loadCatalog()
        #expect(model.canClearCache)

        model.selection = "Arimo"
        let load = Task { await model.loadPreview() }
        while model.canClearCache { await Task.yield() }
        model.selection = "JetBrainsMono"  // moved on; Arimo's download is still running
        #expect(!model.canClearCache)

        await gate.open()
        await load.value
        #expect(model.canClearCache)
    }
}

/// Holds work until opened.
actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
