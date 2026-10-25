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

    static func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "catalog.json")
    }
}
