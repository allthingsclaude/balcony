import XCTest
@testable import BalconyShared

final class ClaudeProjectHashTests: XCTestCase {

    func testPlainPathReplacesSlashes() {
        XCTAssertEqual(
            ClaudeProjectHash.hash("/Users/dev/Projects/balcony"),
            "-Users-dev-Projects-balcony"
        )
    }

    func testUnderscoresAndDotsCollapseToDash() {
        // The bug this guards: the old `/`-only transform left '.' and '_' intact, so these
        // resolved to a directory Claude Code never created.
        XCTAssertEqual(ClaudeProjectHash.hash("/Users/dev/my_app"), "-Users-dev-my-app")
        XCTAssertEqual(ClaudeProjectHash.hash("/Users/dev/.config"), "-Users-dev--config")
        XCTAssertEqual(ClaudeProjectHash.hash("/Users/dev/a.b_c/d"), "-Users-dev-a-b-c-d")
    }

    func testLegacyHashOnlyReplacesSlash() {
        XCTAssertEqual(ClaudeProjectHash.legacyHash("/Users/dev/my_app"), "-Users-dev-my_app")
    }

    func testHashEqualsLegacyWhenNoDotsOrUnderscores() {
        // For the common case both transforms agree, so the locator's fallback is a no-op.
        let path = "/Users/dev/Projects/balcony"
        XCTAssertEqual(ClaudeProjectHash.hash(path), ClaudeProjectHash.legacyHash(path))
    }
}
