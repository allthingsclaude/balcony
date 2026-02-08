import XCTest
@testable import BalconyShared

final class ModelTests: XCTestCase {

    func testSessionEncoding() throws {
        let session = Session(
            id: "test-123",
            projectPath: "/Users/dev/projects/myapp",
            status: .active
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Session.self, from: data)

        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.projectPath, session.projectPath)
        XCTAssertEqual(decoded.projectName, "myapp")
        XCTAssertEqual(decoded.status, .active)
    }

    func testAwaySignalsComputation() {
        // Present
        var signals = AwaySignals(bleRSSI: -40, idleSeconds: 10, screenLocked: false, onLocalNetwork: true)
        XCTAssertEqual(signals.computeStatus(), .present)

        // Idle (high idle time)
        signals = AwaySignals(bleRSSI: -40, idleSeconds: 130, screenLocked: false, onLocalNetwork: true)
        XCTAssertEqual(signals.computeStatus(), .idle)

        // Locked
        signals = AwaySignals(bleRSSI: -40, idleSeconds: 10, screenLocked: true, onLocalNetwork: true)
        XCTAssertEqual(signals.computeStatus(), .locked)

        // Away
        signals = AwaySignals(bleRSSI: nil, idleSeconds: 10, screenLocked: false, onLocalNetwork: false)
        XCTAssertEqual(signals.computeStatus(), .away)
    }
}
