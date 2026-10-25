import SwiftUI

/// The few colors the app uses beyond the system's.
enum Theme {
    /// Teal from the app icon, deep enough for white text on prominent buttons.
    static let accent = Color(red: 0.03, green: 0.57, blue: 0.70)

    /// The preview card is a terminal, so it stays dark in light mode too.
    enum Terminal {
        static let background = Color(red: 0.10, green: 0.11, blue: 0.15)
        static let foreground = Color(red: 0.79, green: 0.83, blue: 0.96)
        static let dim = Color.white.opacity(0.35)
        static let blue = Color(red: 0.48, green: 0.64, blue: 0.97)
        static let green = Color(red: 0.62, green: 0.81, blue: 0.42)
        static let ink = background
    }
}
