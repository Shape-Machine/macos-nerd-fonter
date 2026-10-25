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
            for file in Self.fontFiles(in: dir) where Self.mightBeNerdFont(file) {
                let isReleaseNamed = FontFace.parse(fileName: file.lastPathComponent) != nil
                guard let metadata = readMetadata(file),
                      let base = Self.baseName(fromFamilyName: metadata.familyName),
                      let family = families.first(where: {
                          Self.belongs(base, to: $0.patchedName, isReleaseNamed: isReleaseNamed)
                      })
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

    /// Whether a font whose family base is `base` belongs to the catalog family `patchedName`.
    ///
    /// Typefaces extend the family name (JetBrainsMonoNL, MesloLGS, GohuFont11). Official release file
    /// names are strong evidence, so any extension is fine for them. Other files only get short
    /// typeface codes, so Powerlevel10k's "MesloLGS NF" counts as Meslo but a different font that merely
    /// shares a prefix ("HackGen Console NF") doesn't count as Hack — and can't be trashed with it.
    static func belongs(_ base: String, to patchedName: String, isReleaseNamed: Bool) -> Bool {
        guard base.hasPrefix(patchedName) else { return false }
        let rest = base.dropFirst(patchedName.count)
        return isReleaseNamed || rest.isEmpty || rest.wholeMatch(of: /[A-Z0-9]{1,3}/) != nil
    }

    /// Cheap file-name check, so we only read the name table of likely candidates. Covers release
    /// names ("…NerdFont…") and "NF" builds such as Powerlevel10k's "MesloLGS NF Regular.ttf".
    static func mightBeNerdFont(_ file: URL) -> Bool {
        let name = file.deletingPathExtension().lastPathComponent
        return name.localizedCaseInsensitiveContains("nerd") || name.contains(/\bNF[MP]?\b/)
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

        let fonts: [URL]
        do {
            try await FontStore.tar(["-xJf", archive.path, "-C", staging.path])
            fonts = Self.fontFiles(in: staging)
            guard !fonts.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        } catch {
            // Don't let a broken download stick around and defeat retries.
            try? fm.removeItem(at: archive)
            throw error
        }

        // All or nothing: existing files are set aside, and restored if any move fails,
        // so a failed install never leaves the family deleted or half replaced.
        let backups = staging.appending(path: ".backups")
        try fm.createDirectory(at: backups, withIntermediateDirectories: true)
        try fm.createDirectory(at: userFonts, withIntermediateDirectories: true)
        var moved: [(destination: URL, backup: URL?)] = []
        do {
            for font in fonts {
                let destination = userFonts.appending(path: font.lastPathComponent)
                var backup: URL?
                if fm.fileExists(atPath: destination.path) {
                    backup = backups.appending(path: font.lastPathComponent)
                    try fm.moveItem(at: destination, to: backup!)
                }
                moved.append((destination, backup))
                try fm.moveItem(at: font, to: destination)
            }
        } catch {
            for (destination, backup) in moved.reversed() {
                try? fm.removeItem(at: destination)
                if let backup { try? fm.moveItem(at: backup, to: destination) }
            }
            throw error
        }
        return moved.map(\.destination)
    }

    /// Moves the family's files to the Trash. System-wide installs are left alone.
    public func uninstall(_ installation: Installation) async throws {
        guard !installation.isSystemWide else { throw CocoaError(.fileWriteNoPermission) }
        for file in installation.files {
            try remove(file)
        }
    }
}
