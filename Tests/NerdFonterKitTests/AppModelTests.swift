import NerdFonterKit
import Testing

@MainActor
struct AppModelTests {
    @Test func startsWithEmptySearch() {
        #expect(AppModel().searchText.isEmpty)
    }
}
