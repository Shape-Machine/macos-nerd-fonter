import CoreText
import Foundation

/// One font file from a release, e.g. `JetBrainsMonoNerdFontMono-Regular.ttf`.
public struct FontFace: Identifiable, Hashable, @unchecked Sendable {
    public enum Variant: String, CaseIterable, Identifiable, Sendable {
        case standard = "Standard", mono = "Mono", propo = "Propo"
        public var id: Self { self }
    }

    public let url: URL
    /// Typeface within the family, e.g. "JetBrainsMono" or "JetBrainsMonoNL".
    public let baseName: String
    public let variant: Variant
    // Immutable CF type, safe to share across threads.
    private let descriptor: CTFontDescriptor

    public var id: URL { url }

    /// Returns nil for files that don't follow the release naming scheme or can't be read as fonts.
    public init?(url: URL) {
        guard let (baseName, variant) = Self.parse(fileName: url.lastPathComponent),
              let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first
        else { return nil }
        self.url = url
        self.baseName = baseName
        self.variant = variant
        self.descriptor = descriptor
    }

    /// `JetBrainsMonoNLNerdFontPropo-Bold.ttf` → ("JetBrainsMonoNL", .propo).
    static func parse(fileName: String) -> (baseName: String, variant: Variant)? {
        let stem = fileName.split(separator: "-").dropLast().joined(separator: "-")
        guard let marker = stem.range(of: "NerdFont", options: .backwards) else { return nil }
        let variant: Variant
        switch stem[marker.upperBound...] {
        case "": variant = .standard
        case "Mono": variant = .mono
        case "Propo": variant = .propo
        default: return nil
        }
        return (String(stem[..<marker.lowerBound]), variant)
    }

    public func font(size: CGFloat) -> CTFont {
        CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    public static func == (lhs: FontFace, rhs: FontFace) -> Bool { lhs.url == rhs.url }
    public func hash(into hasher: inout Hasher) { hasher.combine(url) }
}
