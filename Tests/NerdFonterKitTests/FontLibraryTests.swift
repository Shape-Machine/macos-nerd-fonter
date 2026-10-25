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

    @Test func fileNameFilterCoversNFBuilds() {
        #expect(FontLibrary.mightBeNerdFont(URL(filePath: "/f/JetBrainsMonoNerdFont-Regular.ttf")))
        #expect(FontLibrary.mightBeNerdFont(URL(filePath: "/f/MesloLGS NF Regular.ttf")))
        #expect(FontLibrary.mightBeNerdFont(URL(filePath: "/f/Hack NFM Bold.ttf")))
        #expect(!FontLibrary.mightBeNerdFont(URL(filePath: "/f/Hack-Regular.ttf")))
        #expect(!FontLibrary.mightBeNerdFont(URL(filePath: "/f/NFL Sans.ttf")))
    }

    @Test func detectsPowerlevel10kMeslo() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let library = FontLibrary(
            userFonts: root.appending(path: "User"), systemFonts: root.appending(path: "System"),
            readMetadata: { _ in .init(familyName: "MesloLGS NF", version: "Version 2.1.0") })
        try Fixtures.touch(library.userFonts, ["MesloLGS NF Regular.ttf", "MesloLGS NF Bold.ttf"])

        let installed = await library.scan(catalog: [Self.family("MesloLG", folder: "Meslo")])
        #expect(installed["Meslo"]?.files.count == 2)
        #expect(installed["Meslo"]?.nerdFontsVersion == nil)
    }

    @Test func failedInstallRestoresExistingFiles() async throws {
        let fm = FileManager.default
        let library = Fixtures.library()
        try Fixtures.touch(library.userFonts, ["TestNerdFont-A.ttf", "TestNerdFont-B.ttf"])
        // A locked file can't be moved, so the install fails on B after replacing A.
        let locked = library.userFonts.appending(path: "TestNerdFont-B.ttf")
        try fm.setAttributes([.immutable: true], ofItemAtPath: locked.path)
        defer { try? fm.setAttributes([.immutable: false], ofItemAtPath: locked.path) }
        let archive = try FontStoreTests.makeArchive(["TestNerdFont-A.ttf", "TestNerdFont-B.ttf", "TestNerdFont-C.ttf"])

        await #expect(throws: (any Error).self) { try await library.install(archive: archive) }

        let contents = try fm.contentsOfDirectory(atPath: library.userFonts.path).sorted()
        #expect(contents == ["TestNerdFont-A.ttf", "TestNerdFont-B.ttf"])
        // A is the original (empty) file again, not the archive's copy.
        #expect(try Data(contentsOf: library.userFonts.appending(path: "TestNerdFont-A.ttf")).isEmpty)
    }

    @Test func installDiscardsBrokenArchive() async throws {
        let library = Fixtures.library()
        let broken = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).tar.xz")
        try Data("not an archive".utf8).write(to: broken)

        await #expect(throws: (any Error).self) { try await library.install(archive: broken) }
        #expect(!FileManager.default.fileExists(atPath: broken.path))
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
