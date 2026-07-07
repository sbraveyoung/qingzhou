#if os(macOS)
import XCTest
import QingzhouCore
import QingzhouLogging
@testable import QingzhouApp

/// 来源 App 回填（macOS content filter → XPC map → backfillSourceApps）：
/// map 常晚于连接 ingest 才就绪，回填要补上活跃连接的标注；
/// 但带时间戳的条目按「端口+时间窗」匹配，端口复用不再误标老连接。
@MainActor
final class SourceAppBackfillTests: XCTestCase {
    var tmpDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("srcapp-test-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
        try await super.tearDown()
    }

    private func makeState() -> AppState {
        AppState(
            logger: Logger(capacity: 100, minimumLevel: .debug),
            persistence: Persistence(directory: tmpDir)
        )
    }

    private func conn(port: String, openedAt: Date, closedAt: Date? = nil) -> Connection {
        Connection(
            targetHost: "example.com",
            sourceAddress: "10.0.10.1:\(port)",
            targetAddress: "1.2.3.4:443",
            type: .https,
            route: "PROXY",
            matchedRule: "",
            openedAt: openedAt,
            closedAt: closedAt
        )
    }

    func testLateMapBackfillsActiveConnectionWithinWindow() {
        let state = makeState()
        let opened = Date()
        state.connectionTracker.ingest(conn(port: "50000", openedAt: opened))
        XCTAssertNil(state.connections.first?.sourceApp)

        // map 晚到（下一轮 XPC 轮询才拿到），flow 观测时刻 ≈ 建连时刻 → 补上
        let seen = Int(opened.timeIntervalSince1970)
        state.sourceAppMap = SourceAppMap(raw: ["50000": "com.apple.Safari\t\(seen)"])
        state.backfillSourceApps()
        XCTAssertEqual(state.connections.first?.sourceApp, "com.apple.Safari")
    }

    func testPortReuseDoesNotMislabelOldActiveConnection() {
        let state = makeState()
        // 老连接 1 小时前建立、仍活跃、没标注（比如启用过滤前就存在）
        let opened = Date().addingTimeInterval(-3600)
        state.connectionTracker.ingest(conn(port: "50000", openedAt: opened))

        // 同端口刚被别的 App 复用，filter 观测到新鲜 flow → 老连接不能被认领
        let now = Int(Date().timeIntervalSince1970)
        state.sourceAppMap = SourceAppMap(raw: ["50000": "com.tencent.WeChat\t\(now)"])
        state.backfillSourceApps()
        XCTAssertNil(state.connections.first?.sourceApp)
    }

    func testClosedConnectionIsNeverBackfilled() {
        let state = makeState()
        let opened = Date()
        state.connectionTracker.ingest(conn(port: "50000", openedAt: opened, closedAt: opened.addingTimeInterval(1)))

        state.sourceAppMap = SourceAppMap(raw: ["50000": "com.apple.Safari\t\(Int(opened.timeIntervalSince1970))"])
        state.backfillSourceApps()
        XCTAssertNil(state.connections.first?.sourceApp)
    }
}
#endif
