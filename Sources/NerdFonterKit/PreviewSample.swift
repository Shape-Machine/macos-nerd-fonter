/// Default preview content: a prompt, a little code, and popular glyphs.
public enum PreviewSample {
    public struct Glyph: Identifiable, Sendable {
        public let name: String
        public let character: String
        public var id: String { name }

        init(_ name: String, _ scalar: UInt32) {
            self.name = name
            self.character = String(Character(Unicode.Scalar(scalar)!))
        }
    }

    public static let text = """
        \u{F07C} ~/code/nerd-fonter \u{E0B0} \u{E0A0} main \u{E0B0}
        func greet(_ name: String) -> String {
            // 0O 1lI |  != -> => <= ===
            return "Hello, \\(name)!"
        }
        """

    public static let glyphs: [Glyph] = [
        Glyph("nf-pl-branch", 0xE0A0),
        Glyph("nf-pl-left_hard_divider", 0xE0B0),
        Glyph("nf-dev-git", 0xE702),
        Glyph("nf-oct-git_branch", 0xF418),
        Glyph("nf-fa-github", 0xF09B),
        Glyph("nf-fa-folder", 0xF07B),
        Glyph("nf-fa-folder_open", 0xF07C),
        Glyph("nf-fa-terminal", 0xF120),
        Glyph("nf-fa-code", 0xF121),
        Glyph("nf-dev-apple", 0xE711),
        Glyph("nf-linux-tux", 0xF31A),
        Glyph("nf-dev-swift", 0xE755),
        Glyph("nf-dev-python", 0xE73C),
        Glyph("nf-dev-rust", 0xE7A8),
        Glyph("nf-dev-go", 0xE724),
        Glyph("nf-dev-javascript", 0xE781),
        Glyph("nf-dev-docker", 0xE7B0),
        Glyph("nf-custom-vim", 0xE62B),
        Glyph("nf-fa-bug", 0xF188),
        Glyph("nf-fa-gear", 0xF013),
        Glyph("nf-fa-lock", 0xF023),
        Glyph("nf-md-rocket_launch", 0xF14DE),
    ]
}
