import CoreText
import Foundation

/// A Nerd Font family found in the user's or the system's Fonts folder.
public struct Installation: Equatable, Sendable {
    public var files: [URL]
    /// Nerd Fonts release the files were patched with, e.g. "3.3.0"; nil when they don't say.
    public var nerdFontsVersion: String?
    /// Any file in `/Library/Fonts`: removing it needs admin rights, so we leave it alone.
    public var isSystemWide: Bool
}

/// Reads, installs, and removes Nerd Fonts in the Fonts folders.
public struct FontLibrary: Sendable {
    public struct Metadata: Sendable {
        public var familyName: String
        public var version: String?
    }

    let userFonts: URL
    let systemFonts: URL
    let readMetadata: @Sendable (URL) -> Metadata?
    let remove: @Sendable (URL) throws -> Void

    public init(
        userFonts: URL, systemFonts: URL,
        readMetadata: @escaping @Sendable (URL) -> Metadata? = Self.coreTextMetadata,
        remove: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) {
        self.userFonts = userFonts
        self.systemFonts = systemFonts
        self.readMetadata = readMetadata
        self.remove = remove
    }

    /// `~/Library/Fonts` and `/Library/Fonts`; uninstalling moves files to the Trash.
    public static let live = FontLibrary(
        userFonts: URL.libraryDirectory.appending(path: "Fonts"),
        systemFonts: URL(filePath: "/Library/Fonts"))

    // MARK: Detection

    /// Finds installed catalog families, however they were installed (this app, Homebrew, by hand).
    public func scan(catalog: [FontFamily]) async -> [FontFamily.ID: Installation] {
        // Longest names first, so "IosevkaTerm…" matches IosevkaTerm rather than Iosevka.
        let families = catalog.sorted { $0.patchedName.count > $1.patchedName.count }
        var result: [FontFamily.ID: Installation] = [:]
        for (dir, isSystemWide) in [(userFonts, false), (systemFonts, true)] {
            for file in Self.fontFiles(in: dir) where file.lastPathComponent.localizedCaseInsensitiveContains("nerd") {
                guard let metadata = readMetadata(file),
                      let base = Self.baseName(fromFamilyName: metadata.familyName),
                      let family = families.first(where: { base.hasPrefix($0.patchedName) })
                else { continue }
                var installation = result[family.id] ?? Installation(files: [], isSystemWide: false)
                installation.files.append(file)
                installation.isSystemWide = installation.isSystemWide || isSystemWide
                // Report the oldest version found, so a partly updated family still shows as outdated.
                if let version = metadata.version.flatMap(Self.nerdFontsVersion(from:)),
                   installation.nerdFontsVersion.map({ version.compare($0, options: .numeric) == .orderedAscending }) ?? true {
                    installation.nerdFontsVersion = version
                }
                result[family.id] = installation
            }
        }
        return result
    }

    /// "JetBrainsMonoNL Nerd Font Propo" → "JetBrainsMonoNL". Long names use "NF", "NFM", "NFP".
    static func baseName(fromFamilyName name: String) -> String? {
        guard let match = name.firstMatch(of: /^(.+?) (?:Nerd Font|NF[MP]?)(?: |$)/) else { return nil }
        return String(match.1)
    }

    /// "Version 2.304; ttfautohint (v1.8.4);Nerd Fonts 3.3.0" → "3.3.0".
    static func nerdFontsVersion(from version: String) -> String? {
        version.firstMatch(of: /Nerd Fonts (\d+(?:\.\d+)*)/).map { String($0.1) }
    }

    public static let coreTextMetadata: @Sendable (URL) -> Metadata? = { url in
        guard let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first,
              let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String
        else { return nil }
        let font = CTFontCreateWithFontDescriptor(descriptor, 1, nil)
        return Metadata(familyName: family, version: CTFontCopyName(font, kCTFontVersionNameKey) as String?)
    }

    static func fontFiles(in dir: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { ["ttf", "otf"].contains($0.pathExtension.lowercased()) }
    }

    // MARK: Install / uninstall

    /// Unpacks every font in `archive` into the user's Fonts folder, replacing same-named files.
    /// Unpacks next to the archive so the final moves stay on one volume.
    public func install(archive: URL) async throws -> [URL] {
        let fm = FileManager.default
        let staging = archive.deletingLastPathComponent().appending(path: ".install-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        try await FontStore.tar(["-xJf", archive.path, "-C", staging.path])
        let fonts = Self.fontFiles(in: staging)
        guard !fonts.isEmpty else { throw CocoaError(.fileReadCorruptFile) }

        try fm.createDirectory(at: userFonts, withIntermediateDirectories: true)
        return try fonts.map { font in
            let destination = userFonts.appending(path: font.lastPathComponent)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: font, to: destination)
            return destination
        }
    }

    /// Moves the family's files to the Trash. System-wide installs are left alone.
    public func uninstall(_ installation: Installation) async throws {
        guard !installation.isSystemWide else { throw CocoaError(.fileWriteNoPermission) }
        for file in installation.files {
            try remove(file)
        }
    }
}
