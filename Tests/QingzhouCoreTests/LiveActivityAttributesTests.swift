import XCTest
@testable import QingzhouCore

final class LiveActivityAttributesTests: XCTestCase {
    private func roundTrip(_ state: QingzhouActivityContentState) throws -> QingzhouActivityContentState {
        let data = try JSONEncoder().encode(state)
        return try JSONDecoder().decode(QingzhouActivityContentState.self, from: data)
    }

    func testContentStateCodableRoundTripConnected() throws {
        let since = Date(timeIntervalSince1970: 1_700_000_000)
        let state = QingzhouActivityContentState(
            phase: .connected,
            connectedSince: since,
            uploadSpeedBps: 12_345,
            downloadSpeedBps: 987_654,
            uploadBytes: 1_000_000,
            downloadBytes: 8_000_000
        )
        let decoded = try roundTrip(state)
        XCTAssertEqual(decoded, state)
        XCTAssertEqual(decoded.phase, .connected)
        XCTAssertEqual(decoded.connectedSince, since)
        XCTAssertEqual(decoded.downloadSpeedBps, 987_654)
    }

    func testContentStateCodableRoundTripConnectingNilSince() throws {
        let state = QingzhouActivityContentState(phase: .connecting)
        let decoded = try roundTrip(state)
        XCTAssertEqual(decoded, state)
        XCTAssertNil(decoded.connectedSince)
        XCTAssertEqual(decoded.phase, .connecting)
    }

    func testAllPhasesRoundTrip() throws {
        for phase in [QingzhouActivityContentState.Phase.connecting, .connected, .disconnecting] {
            let decoded = try roundTrip(QingzhouActivityContentState(phase: phase))
            XCTAssertEqual(decoded.phase, phase)
        }
    }

    func testInitFromTrafficStatsMapsFields() {
        let traffic = TrafficStats(
            uploadBytes: 111,
            downloadBytes: 222,
            uploadSpeedBps: 333,
            downloadSpeedBps: 444,
            activeConnections: 5,
            sampledAt: Date()
        )
        let since = Date()
        let state = QingzhouActivityContentState(phase: .connected, connectedSince: since, traffic: traffic)
        XCTAssertEqual(state.phase, .connected)
        XCTAssertEqual(state.connectedSince, since)
        XCTAssertEqual(state.uploadBytes, 111)
        XCTAssertEqual(state.downloadBytes, 222)
        XCTAssertEqual(state.uploadSpeedBps, 333)
        XCTAssertEqual(state.downloadSpeedBps, 444)
    }

    func testHashableEquatable() {
        let a = QingzhouActivityContentState(phase: .connected, uploadSpeedBps: 1)
        let b = QingzhouActivityContentState(phase: .connected, uploadSpeedBps: 1)
        let c = QingzhouActivityContentState(phase: .connected, uploadSpeedBps: 2)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
        XCTAssertNotEqual(a, c)
    }
}
