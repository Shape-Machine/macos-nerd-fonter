import Foundation

/// Loads the catalog, hitting the network at most once a day.
public struct CatalogStore: Sendable {
    public typealias Fetch = @Sendable (URL) async throws -> Data

    static let maxAge: TimeInterval = 24 * 60 * 60
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest")!

    static func fontsURL(release: String) -> URL {
        URL(string: "https://raw.githubusercontent.com/ryanoasis/nerd-fonts/\(release)/bin/scripts/lib/fonts.json")!
    }

    let cacheFile: URL
    let fetch: Fetch
    let now: @Sendable () -> Date

    public init(cacheFile: URL, fetch: @escaping Fetch, now: @escaping @Sendable () -> Date = Date.init) {
        self.cacheFile = cacheFile
        self.fetch = fetch
        self.now = now
    }

    /// We cache what we need ourselves, so skip URLSession's on-disk HTTP cache.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// Uses `~/Library/Caches/<bundle id>/catalog.json`.
    public static let live = CatalogStore(
        cacheFile: URL.cachesDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "NerdFonter")
            .appending(path: "catalog.json"),
        fetch: { url in
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            return data
        })

    /// Returns the cached catalog if fresh; otherwise fetches. Falls back to a stale cache when offline.
    public func load() async throws -> Catalog {
        let cached = try? JSONDecoder().decode(Catalog.self, from: Data(contentsOf: cacheFile))
        // A negative age means the clock went backwards; treat it as stale.
        if let cached, (0..<Self.maxAge).contains(now().timeIntervalSince(cached.fetchedAt)) {
            return cached
        }
        do {
            let catalog = try await fetchLatest()
            try? FileManager.default.createDirectory(
                at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(catalog).write(to: cacheFile, options: .atomic)
            return catalog
        } catch {
            if let cached { return cached }
            throw error
        }
    }

    private func fetchLatest() async throws -> Catalog {
        struct Release: Decodable { let tag_name: String }
        let release = try JSONDecoder().decode(Release.self, from: await fetch(Self.latestReleaseURL)).tag_name
        let data = try await fetch(Self.fontsURL(release: release))
        return try Catalog.parse(data, release: release, fetchedAt: now())
    }
}
