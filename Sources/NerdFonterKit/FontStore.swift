import Foundation

/// Downloads release archives and extracts preview faces under the app's cache directory.
///
/// Archives are `.tar.xz` (a few MB each). For previews we extract one face per typeface and
/// variant (its Regular, when it has one), since a fully extracted family can run to hundreds of MB.
public struct FontStore: Sendable {
    public typealias Download = @Sendable (URL, _ progress: @escaping @Sendable (Double) -> Void) async throws -> URL

    let root: URL
    let download: Download

    public init(root: URL, download: @escaping Download) {
        self.root = root
        self.download = download
    }

    /// Uses `~/Library/Caches/<bundle id>/fonts`.
    public static let live = FontStore(root: CatalogStore.cacheDirectory.appending(path: "fonts"), download: HTTP.download)

    static func archiveURL(release: String, folderName: String) -> URL {
        URL(string: "https://github.com/ryanoasis/nerd-fonts/releases/download/\(release)/\(folderName).tar.xz")!
    }

    /// Regular faces of every variant, downloading and extracting on first use.
    public func previewFaces(
        for font: FontFamily, release: String, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [FontFace] {
        let fm = FileManager.default
        let dir = root.appending(path: release).appending(path: font.folderName)
        if fm.fileExists(atPath: dir.path) { return Self.faces(in: dir) }

        let archive = try await archive(for: font, release: release, progress: progress)
        let staging = root.appending(path: ".staging-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        do {
            let names = try await Self.tar(["-tJf", archive.path]).split(separator: "\n").map(String.init)
            let picks = Self.previewNames(from: names)
            guard !picks.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            try await Self.tar(["-xJf", archive.path, "-C", staging.path] + picks)
        } catch {
            // Don't let a broken download stick around and defeat retries.
            try? fm.removeItem(at: archive)
            throw error
        }
        try Self.moveIfAbsent(staging, to: dir)
        return Self.faces(in: dir)
    }

    /// Cached `.tar.xz` for a family, downloaded once per release.
    public func archive(for font: FontFamily, release: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let fm = FileManager.default
        let file = root.appending(path: release).appending(path: "\(font.folderName).tar.xz")
        if fm.fileExists(atPath: file.path) { return file }

        let temp = try await download(Self.archiveURL(release: release, folderName: font.folderName), progress)
        defer { try? fm.removeItem(at: temp) }
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.moveIfAbsent(temp, to: file)
        return file
    }

    /// Moves `source` into place unless a concurrent load for the same family got there first.
    static func moveIfAbsent(_ source: URL, to destination: URL) throws {
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch where FileManager.default.fileExists(atPath: destination.path) {}
    }

    /// One file per typeface/variant: its Regular face, or the first face when there is no Regular.
    static func previewNames(from names: [String]) -> [String] {
        let fonts = names.filter { $0.hasSuffix(".ttf") || $0.hasSuffix(".otf") }.sorted()
        let groups = Dictionary(grouping: fonts) { $0.split(separator: "-").dropLast().joined(separator: "-") }
        return groups.values.compactMap { files in
            files.first { $0.hasSuffix("-Regular.ttf") || $0.hasSuffix("-Regular.otf") } ?? files.first
        }.sorted()
    }

    /// Preview faces picked from files already on disk, e.g. an installed family.
    public static func faces(choosingFrom files: [URL]) -> [FontFace] {
        let byName = Dictionary(files.map { ($0.lastPathComponent, $0) }) { first, _ in first }
        return previewNames(from: Array(byName.keys)).compactMap { byName[$0] }.compactMap(FontFace.init(url:))
    }

    static func faces(in dir: URL) -> [FontFace] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap(FontFace.init(url:))
            .sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }

    /// Runs `/usr/bin/tar` off the cooperative thread pool and returns its stdout.
    @discardableResult
    static func tar(_ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(filePath: "/usr/bin/tar")
                process.arguments = arguments
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
                    continuation.resume(returning: String(decoding: data, as: UTF8.self))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
