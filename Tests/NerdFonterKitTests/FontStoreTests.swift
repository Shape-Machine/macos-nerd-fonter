import Foundation
import Testing
@testable import NerdFonterKit

struct FontFaceTests {
    @Test func parsesReleaseFileNames() throws {
        let cases: [(String, String, FontFace.Variant)] = [
            ("JetBrainsMonoNerdFont-Regular.ttf", "JetBrainsMono", .standard),
            ("JetBrainsMonoNLNerdFontMono-Bold.ttf", "JetBrainsMonoNL", .mono),
            ("MonaspiceArNerdFontPropo-Regular.otf", "MonaspiceAr", .propo),
            ("3270NerdFont-SemiCondensed.ttf", "3270", .standard),
        ]
        for (file, base, variant) in cases {
            let parsed = try #require(FontFace.parse(fileName: file))
            #expect(parsed.baseName == base)
            #expect(parsed.variant == variant)
        }
    }

    @Test func readsFamilyNameFromTheFile() throws {
        // FontFace needs a release-style file name, so read a system font through one.
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let copy = dir.appending(path: "TestNerdFontMono-Regular.ttf")
        try FileManager.default.copyItem(at: URL(filePath: "/System/Library/Fonts/Supplemental/Andale Mono.ttf"), to: copy)
        let face = try #require(FontFace(url: copy))
        #expect(face.familyName == "Andale Mono")
    }

    @Test func rejectsOtherFiles() {
        #expect(FontFace.parse(fileName: "LICENSE.txt") == nil)
        #expect(FontFace.parse(fileName: "Hack-Regular.ttf") == nil)
        #expect(FontFace.parse(fileName: "HackNerdFontWeird-Regular.ttf") == nil)
    }
}

struct FontStoreTests {
    let font = FontFamily(
        unpatchedName: "Test", patchedName: "Test", folderName: "Test", description: "",
        licenseId: "OFL-1.1", version: "1.0", isMonospaced: true)

    @Test func previewPrefersRegularPerVariant() {
        let names = [
            "LICENSE", "README.md",
            "ANerdFont-Bold.ttf", "ANerdFont-Regular.ttf",
            "ANerdFontMono-Italic.ttf", "ANerdFontMono-Regular.ttf",
            "BNerdFont-Light.otf", "BNerdFont-Medium.otf",
        ]
        #expect(FontStore.previewNames(from: names) == [
            "ANerdFont-Regular.ttf", "ANerdFontMono-Regular.ttf", "BNerdFont-Light.otf",
        ])
    }

    @Test func extractsOnlyRegularFacesAndCaches() async throws {
        let archive = try Self.makeArchive([
            "TestNerdFont-Regular.ttf", "TestNerdFont-Bold.ttf",
            "TestNerdFontMono-Regular.ttf", "TestNerdFontPropo-Regular.ttf",
        ])
        let downloads = Counter()
        let store = Self.store(serving: archive, counter: downloads)

        let faces = try await store.previewFaces(for: font, release: "v1", progress: { _ in })
        #expect(faces.map(\.url.lastPathComponent) == [
            "TestNerdFont-Regular.ttf", "TestNerdFontMono-Regular.ttf", "TestNerdFontPropo-Regular.ttf",
        ])
        #expect(Set(faces.map(\.variant)) == Set(FontFace.Variant.allCases))

        _ = try await store.previewFaces(for: font, release: "v1", progress: { _ in })
        #expect(downloads.value == 1)
    }

    @Test func fallsBackWhenNoRegularFace() async throws {
        let archive = try Self.makeArchive(["TestNerdFont-Book.ttf", "TestNerdFont-Heavy.ttf"])
        let store = Self.store(serving: archive, counter: Counter())
        let faces = try await store.previewFaces(for: font, release: "v1", progress: { _ in })
        #expect(faces.map(\.url.lastPathComponent) == ["TestNerdFont-Book.ttf"])
    }

    @Test func keepsVariantsWithoutRegularAlongsideOnesWithIt() async throws {
        let archive = try Self.makeArchive(["TestNerdFont-Regular.ttf", "TestNerdFontMono-Book.ttf"])
        let store = Self.store(serving: archive, counter: Counter())
        let faces = try await store.previewFaces(for: font, release: "v1", progress: { _ in })
        #expect(faces.map(\.url.lastPathComponent) == ["TestNerdFont-Regular.ttf", "TestNerdFontMono-Book.ttf"])
    }

    @Test func discardsBrokenArchiveSoRetriesDownloadAgain() async throws {
        let broken = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).tar.xz")
        try Data("not an archive".utf8).write(to: broken)
        let downloads = Counter()
        let store = Self.store(serving: broken, counter: downloads)

        for _ in 0..<2 {
            await #expect(throws: (any Error).self) {
                try await store.previewFaces(for: font, release: "v1", progress: { _ in })
            }
        }
        #expect(downloads.value == 2)
    }

    @Test func overlappingLoadsBothSucceed() async throws {
        let archive = try Self.makeArchive(["TestNerdFont-Regular.ttf"])
        let store = Self.store(serving: archive, counter: Counter())
        async let first = store.previewFaces(for: font, release: "v1", progress: { _ in })
        async let second = store.previewFaces(for: font, release: "v1", progress: { _ in })
        let (a, b) = try await (first, second)
        #expect(a.count == 1)
        #expect(b.count == 1)
    }

    @Test func trimDropsOtherReleasesLeftoversAndLeastRecentlyUsed() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: UUID().uuidString)
        let current = root.appending(path: "v2")
        func write(_ path: String, bytes: Int, age: TimeInterval) throws {
            let url = root.appending(path: path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(count: bytes).write(to: url)
            // Writing bumps the folder's date too, so age both.
            for item in [url, url.deletingLastPathComponent()] {
                try fm.setAttributes([.modificationDate: Date() - age], ofItemAtPath: item.path)
            }
        }
        try write("v1/Old.tar.xz", bytes: 10, age: 0)
        try write(".staging-x/A-Regular.ttf", bytes: 10, age: 0)
        try write("v2/.install-x/A-Regular.ttf", bytes: 10, age: 0)
        try write("v2/Recent.tar.xz", bytes: 200_000, age: 10)
        try write("v2/Recent/R-Regular.ttf", bytes: 200_000, age: 10)
        try write("v2/Stale.tar.xz", bytes: 200_000, age: 1000)
        try write("v2/Stale/S-Regular.ttf", bytes: 200_000, age: 1000)

        await FontStore(root: root) { _, _ in throw URLError(.unknown) }.trim(keeping: "v2", limit: 500_000)

        #expect(try fm.contentsOfDirectory(atPath: root.path) == ["v2"])
        #expect(try fm.contentsOfDirectory(atPath: current.path).sorted() == ["Recent", "Recent.tar.xz"])
    }

    @Test func cacheHitsCountAsRecentUse() async throws {
        let archive = try Self.makeArchive(["TestNerdFont-Regular.ttf"])
        let store = Self.store(serving: archive, counter: Counter())
        _ = try await store.previewFaces(for: font, release: "v1", progress: { _ in })
        let dir = store.root.appending(path: "v1/Test")
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: dir.path)

        _ = try await store.previewFaces(for: font, release: "v1", progress: { _ in })
        let used = try dir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        #expect(try #require(used) > Date() - 60)
    }

    // MARK: Helpers

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = 0
        var value: Int { lock.withLock { _value } }
        func increment() { lock.withLock { _value += 1 } }
    }

    static func store(serving archive: URL, counter: Counter) -> FontStore {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        return FontStore(root: root) { _, progress in
            counter.increment()
            progress(1)
            // Real downloads hand over a temp file the store moves, so hand over a copy.
            let copy = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.copyItem(at: archive, to: copy)
            return copy
        }
    }

    /// Builds a `.tar.xz` whose entries are copies of a real system font under release-style names.
    static func makeArchive(_ names: [String]) throws -> URL {
        let fm = FileManager.default
        let source = URL(filePath: "/System/Library/Fonts/Supplemental/Andale Mono.ttf")
        let dir = fm.temporaryDirectory.appending(path: UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in names + ["LICENSE"] {
            try fm.copyItem(at: source, to: dir.appending(path: name))
        }
        let archive = fm.temporaryDirectory.appending(path: "\(UUID().uuidString).tar.xz")
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/tar")
        process.arguments = ["-cJf", archive.path, "-C", dir.path] + names + ["LICENSE"]
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
        return archive
    }
}
