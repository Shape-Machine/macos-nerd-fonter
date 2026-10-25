import Foundation
import Testing
@testable import NerdFonterKit

struct CatalogTests {
    @Test func parsesSortsAndDecodesEntities() throws {
        let catalog = try Catalog.parse(Fixtures.fontsJSON, release: "v3.5.1", fetchedAt: .now)
        #expect(catalog.release == "v3.5.1")
        #expect(catalog.fonts.map(\.name) == ["Arimo", "JetBrains Mono", "Source Code Pro"])
        #expect(catalog.fonts[2].description == "Lines & curves")
        #expect(catalog.fonts[2].id == "SourceCodePro")
    }
}

struct CatalogStoreTests {
    @Test func fetchesAndCachesWhenNoCache() async throws {
        let server = Fixtures.Server()
        let file = Fixtures.tempFile()
        let catalog = try await Fixtures.store(server, cacheFile: file).load()
        #expect(catalog.fonts.count == 3)
        #expect(server.requests == 2)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func usesFreshCacheWithoutNetwork() async throws {
        let file = Fixtures.tempFile()
        let start = Date.now
        _ = try await Fixtures.store(Fixtures.Server(), cacheFile: file, now: start).load()

        let server = Fixtures.Server()
        let catalog = try await Fixtures.store(server, cacheFile: file, now: start + 3600).load()
        #expect(catalog.fonts.count == 3)
        #expect(server.requests == 0)
    }

    @Test func refetchesStaleCache() async throws {
        let file = Fixtures.tempFile()
        let start = Date.now
        _ = try await Fixtures.store(Fixtures.Server(), cacheFile: file, now: start).load()

        let server = Fixtures.Server()
        let later = start + 2 * 86_400
        let catalog = try await Fixtures.store(server, cacheFile: file, now: later).load()
        #expect(server.requests == 2)
        #expect(catalog.fetchedAt == later)
    }

    @Test func refetchesWhenClockMovedBackwards() async throws {
        let file = Fixtures.tempFile()
        let start = Date.now
        _ = try await Fixtures.store(Fixtures.Server(), cacheFile: file, now: start).load()

        let server = Fixtures.Server()
        _ = try await Fixtures.store(server, cacheFile: file, now: start - 3600).load()
        #expect(server.requests == 2)
    }

    @Test func fallsBackToStaleCacheWhenOffline() async throws {
        let file = Fixtures.tempFile()
        let start = Date.now
        _ = try await Fixtures.store(Fixtures.Server(), cacheFile: file, now: start).load()

        let catalog = try await Fixtures.store(Fixtures.Server(offline: true), cacheFile: file, now: start + 2 * 86_400).load()
        #expect(catalog.fetchedAt == start)
    }

    @Test func throwsWhenOfflineWithoutCache() async {
        await #expect(throws: URLError.self) {
            try await Fixtures.store(Fixtures.Server(offline: true), cacheFile: Fixtures.tempFile()).load()
        }
    }
}
