import Foundation

/// One Nerd Font family, as listed in the release's `fonts.json`.
public struct FontFamily: Codable, Hashable, Identifiable, Sendable {
    /// Original typeface name, e.g. "JetBrains Mono". Used for display.
    public let unpatchedName: String
    /// Name used in installed family names, e.g. "JetBrainsMono" → "JetBrainsMono Nerd Font".
    public let patchedName: String
    /// Release asset name, e.g. "JetBrainsMono" → "JetBrainsMono.tar.xz".
    public let folderName: String
    public let description: String
    public let licenseId: String
    /// Version of the original typeface (not of Nerd Fonts).
    public let version: String
    public let isMonospaced: Bool

    public var id: String { folderName }
    public var name: String { unpatchedName }
}

/// The list of font families in one Nerd Fonts release.
public struct Catalog: Codable, Equatable, Sendable {
    /// Release tag, e.g. "v3.5.1".
    public let release: String
    public let fonts: [FontFamily]
    public let fetchedAt: Date

    public init(release: String, fonts: [FontFamily], fetchedAt: Date) {
        self.release = release
        self.fonts = fonts
        self.fetchedAt = fetchedAt
    }

    /// Parses upstream `fonts.json` and sorts families by display name.
    public static func parse(_ data: Data, release: String, fetchedAt: Date) throws -> Catalog {
        struct File: Decodable { let fonts: [FontFamily] }
        let fonts = try JSONDecoder().decode(File.self, from: data).fonts
            .map(\.withDecodedEntities)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return Catalog(release: release, fonts: fonts, fetchedAt: fetchedAt)
    }
}

extension FontFamily {
    /// Upstream descriptions contain HTML entities such as `&amp;`.
    fileprivate var withDecodedEntities: FontFamily {
        FontFamily(
            unpatchedName: unpatchedName, patchedName: patchedName, folderName: folderName,
            description: description
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&amp;", with: "&"),
            licenseId: licenseId, version: version, isMonospaced: isMonospaced)
    }
}
