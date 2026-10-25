import Foundation
@testable import NerdFonterKit

enum Fixtures {
    static let fontsJSON = Data("""
    {"fonts": [
      {"unpatchedName": "JetBrains Mono", "patchedName": "JetBrainsMono", "folderName": "JetBrainsMono",
       "description": "Official font", "licenseId": "OFL-1.1", "version": "2.304", "isMonospaced": true,
       "RFN": false, "caskName": "jetbrains-mono"},
      {"unpatchedName": "Source Code Pro", "patchedName": "SauceCodePro", "folderName": "SourceCodePro",
       "description": "Lines &amp; curves", "licenseId": "OFL-1.1", "version": "2.042", "isMonospaced": true},
      {"unpatchedName": "Arimo", "patchedName": "Arimo", "folderName": "Arimo",
       "description": "Like Arial", "licenseId": "Apache-2.0", "version": "1.33", "isMonospaced": false}
    ]}
    """.utf8)

    static let releaseJSON = Data(#"{"tag_name": "v3.5.1", "assets": []}"#.utf8)

    /// Serves the GitHub release and fonts.json; counts requests.
    final class Server: @unchecked Sendable {
        private let lock = NSLock()
        private var _requests = 0
        var requests: Int { lock.withLock { _requests } }
        let offline: Bool

        init(offline: Bool = false) { self.offline = offline }

        func fetch(_ url: URL) throws -> Data {
            lock.withLock { _requests += 1 }
            if offline { throw URLError(.notConnectedToInternet) }
            if url == CatalogStore.latestReleaseURL { return Fixtures.releaseJSON }
            if url == CatalogStore.fontsURL(release: "v3.5.1") { return Fixtures.fontsJSON }
            throw URLError(.fileDoesNotExist)
        }
    }

    static func store(_ server: Server, cacheFile: URL, now: Date = .now) -> CatalogStore {
        CatalogStore(cacheFile: cacheFile, fetch: { try server.fetch($0) }, now: { now })
    }

    /// A library over empty temp folders. Metadata comes from release-style file names, so tests
    /// don't need real Nerd Font files: `JetBrainsMonoNerdFontMono-Regular.ttf` reads as family
    /// "JetBrainsMono Nerd Font Mono", patched with `version` (or the version in a `@3.3.0` name suffix).
    static func library(version: String = "3.5.1") -> FontLibrary {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        return FontLibrary(
            userFonts: root.appending(path: "User"), systemFonts: root.appending(path: "System"),
            readMetadata: { url in
                let name = url.deletingPathExtension().lastPathComponent
                let fileVersion = name.split(separator: "@").dropFirst().first.map(String.init)
                let fileName = name.split(separator: "@").first.map { "\($0).\(url.pathExtension)" } ?? ""
                guard let (base, variant) = FontFace.parse(fileName: fileName) else { return nil }
                let suffix = variant == .standard ? "" : " \(variant.rawValue)"
                return .init(familyName: "\(base) Nerd Font\(suffix)", version: "Version 1.0;Nerd Fonts \(fileVersion ?? version)")
            },
            remove: { try FileManager.default.removeItem(at: $0) })
    }

    @MainActor
    static func model(
        fontStore: FontStore? = nil, library: FontLibrary = library(), defaults: UserDefaults = defaults()
    ) -> AppModel {
        AppModel(
            store: store(Server(), cacheFile: tempFile()),
            fontStore: fontStore ?? FontStore(root: tempFile()) { _, _ in throw URLError(.notConnectedToInternet) },
            library: library,
            defaults: defaults)
    }

    /// Throwaway defaults, so tests never touch the app's real preferences.
    static func defaults() -> UserDefaults {
        UserDefaults(suiteName: "NerdFonterTests-\(UUID().uuidString)")!
    }

    static func touch(_ dir: URL, _ names: [String]) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in names {
            try Data().write(to: dir.appending(path: name))
        }
    }

    static func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "catalog.json")
    }
}
