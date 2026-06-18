import XCTest
@testable import BalconyShared

/// Wire-crossing enums must decode an unrecognized raw value to `.unknown` rather than
/// throwing, so a single odd member from a newer peer can't fail the whole list decode.
final class EnumFallbackTests: XCTestCase {

    func testSessionStatusUnknownDecodes() throws {
        let json = #""someFutureStatus""#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(SessionStatus.self, from: json), .unknown)
        XCTAssertEqual(try JSONDecoder().decode(SessionStatus.self, from: #""active""#.data(using: .utf8)!), .active)
    }

    func testModelTierUnknownDecodesAndSortsLast() throws {
        let json = #""ultra""#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(ModelTier.self, from: json), .unknown)
        XCTAssertTrue(ModelTier.opus < ModelTier.unknown)
        XCTAssertTrue(ModelTier.haiku < ModelTier.unknown)
    }

    func testSlashCommandSourceUnknownDecodes() throws {
        let json = #""plugin""#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(SlashCommandInfo.Source.self, from: json), .unknown)
    }

    /// The key payoff: a session list containing one unknown status still decodes fully
    /// instead of failing and wiping the list to empty. Encode real Sessions then tamper the
    /// wire string, to stay independent of the exact Codable layout.
    func testSessionListSurvivesOneUnknownStatus() throws {
        let sessions = [
            Session(id: "a", projectPath: "/p", status: .active),
            Session(id: "b", projectPath: "/p", status: .idle),
        ]
        var json = String(data: try JSONEncoder().encode(sessions), encoding: .utf8)!
        // Simulate a newer peer sending a status this build doesn't recognize.
        json = json.replacingOccurrences(of: "\"idle\"", with: "\"brandNewStatus\"")
        let decoded = try JSONDecoder().decode([Session].self, from: json.data(using: .utf8)!)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].status, .active)
        XCTAssertEqual(decoded[1].status, .unknown)
    }
}
