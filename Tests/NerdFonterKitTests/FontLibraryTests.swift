import Foundation
import Testing
@testable import NerdFonterKit

struct FontLibraryTests {
    @Test func parsesFamilyNames() {
        #expect(FontLibrary.baseName(fromFamilyName: "JetBrainsMono Nerd Font") == "JetBrainsMono")
        #expect(FontLibrary.baseName(fromFamilyName: "JetBrainsMonoNL Nerd Font Propo") == "JetBrainsMonoNL")
        #expect(FontLibrary.baseName(fromFamilyName: "Inconsolata LGC Nerd Font Mono") == "Inconsolata LGC")
        #expect(FontLibrary.baseName(fromFamilyName: "AtkynsonMono NFM") == "AtkynsonMono")
        #expect(FontLibrary.baseName(fromFamilyName: "Hack") == nil)
        #expect(FontLibrary.baseName(fromFamilyName: "Nerdy Sans") == nil)
    }

    @Test func parsesNerdFontsVersion() {
        #expect(FontLibrary.nerdFontsVersion(from: "Version 2.304; ttfautohint (v1.8.4);Nerd Fonts 3.3.0") == "3.3.0")
        #expect(FontLibrary.nerdFontsVersion(from: "Version 1.0") == nil)
    }

    @Test func scanMatchesFamiliesAcrossFolders() async throws {
        let catalog = [
            Self.family("Iosevka"), Self.family("IosevkaTerm"), Self.family("JetBrainsMono"), Self.family("MesloLG", folder: "Meslo"),
        ]
        let library = Fixtures.library()
        try Fixtures.touch(library.userFonts, [
            "IosevkaNerdFont-Regular.ttf",
            "IosevkaTermNerdFontMono-Regular.ttf",
            "JetBrainsMonoNerdFont-Regular.ttf",
            "JetBrainsMonoNLNerdFontPropo-Regular@3.3.0.ttf",
            "MynaNerdFont-Regular.ttf",  // not in the catalog
            "Hack-Regular.ttf",  // not a Nerd Font
        ])
        try Fixtures.touch(library.systemFonts, ["MesloLGSNerdFont-Regular.ttf"])

        let installed = await library.scan(catalog: catalog)
        #expect(installed.keys.sorted() == ["Iosevka", "IosevkaTerm", "JetBrainsMono", "Meslo"])
        #expect(installed["Iosevka"]?.files.count == 1)
        #expect(installed["JetBrainsMono"]?.files.count == 2)
        #expect(installed["JetBrainsMono"]?.nerdFontsVersion == "3.3.0")  // oldest wins
        #expect(installed["Iosevka"]?.isSystemWide == false)
        #expect(installed["Meslo"]?.isSystemWide == true)
    }

    @Test func installMovesOnlyFontsAndReplacesExisting() async throws {
        let library = Fixtures.library()
        try Fixtures.touch(library.userFonts, ["TestNerdFont-Regular.ttf"])
        let archive = try FontStoreTests.makeArchive(["TestNerdFont-Regular.ttf", "TestNerdFontMono-Bold.otf"])

        let installed = try await library.install(archive: archive)
        #expect(installed.map(\.lastPathComponent).sorted() == ["TestNerdFont-Regular.ttf", "TestNerdFontMono-Bold.otf"])
        let contents = try FileManager.default.contentsOfDirectory(atPath: library.userFonts.path).sorted()
        #expect(contents == ["TestNerdFont-Regular.ttf", "TestNerdFontMono-Bold.otf"])
        // Replaced with the archive's (non-empty) copy.
        #expect(try Data(contentsOf: library.userFonts.appending(path: "TestNerdFont-Regular.ttf")).count > 0)
    }

    @Test func uninstallRefusesSystemWide() async throws {
        let library = Fixtures.library()
        let installation = Installation(files: [], isSystemWide: true)
        await #expect(throws: CocoaError.self) { try await library.uninstall(installation) }
    }

    static func family(_ patchedName: String, folder: String? = nil) -> FontFamily {
        FontFamily(
            unpatchedName: patchedName, patchedName: patchedName, folderName: folder ?? patchedName,
            description: "", licenseId: "OFL-1.1", version: "1.0", isMonospaced: true)
    }
}
