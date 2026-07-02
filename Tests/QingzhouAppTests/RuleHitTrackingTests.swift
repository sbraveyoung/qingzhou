import XCTest
import QingzhouCore
import QingzhouLogging
@testable import QingzhouApp

/// 自定义规则命中计数的 AppState 侧：埋点入口、独立文件持久化（不进 Snapshot，不上云）、
/// 重启恢复。计数本体逻辑见 RuleHitStatsTests。
@MainActor
final class RuleHitTrackingTests: XCTestCase {
    var tmpDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rule-hit-test-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
        try await super.tearDown()
    }

    private func makeState() -> AppState {
        let state = AppState(
            logger: Logger(capacity: 100, minimumLevel: .debug),
            persistence: Persistence(directory: tmpDir)
        )
        state.ruleHitStatsSaveInterval = 0   // 关掉节流，确定性断言
        return state
    }

    func testRecordRuleHitCountsAndPersistsToSeparateFile() {
        let state = makeState()
        let rule = Rule(type: .domainSuffix, value: "google.com", target: .proxy)
        state.customRules = [rule]

        state.recordRuleHit(rule.id, at: Date())
        state.recordRuleHit(rule.id, at: Date())
        state.recordRuleHit(nil, at: Date())   // 未命中用户规则的连接：不计数、不崩
        XCTAssertEqual(state.ruleHitStats.hitCount(for: rule.id), 2)

        state.persistence.waitForPendingWritesForTesting()
        // 独立文件，不进 Snapshot（隐私约定：Snapshot 会被 iCloud vault 镜像）
        let hitFile = tmpDir.appendingPathComponent("rule-hit-stats.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: hitFile.path))
        let snapshotText = (try? String(contentsOf: tmpDir.appendingPathComponent("state.json"),
                                        encoding: .utf8)) ?? ""
        XCTAssertFalse(snapshotText.contains("hitCount"), "Snapshot 不得混入命中计数字段")

        // 重启恢复
        let reloaded = makeState()
        XCTAssertEqual(reloaded.ruleHitStats.hitCount(for: rule.id), 2)
    }

    func testSaveThrottleHoldsSecondWriteThenFlushLandsIt() {
        let state = makeState()
        state.ruleHitStatsSaveInterval = 3600
        let id = UUID()
        // 首写立即落盘（savedAt 初始为 distantPast，同 domainHistory 语义）
        state.recordRuleHit(id, at: Date())
        state.persistence.waitForPendingWritesForTesting()
        XCTAssertEqual(makeState().ruleHitStats.hitCount(for: id), 1)

        // 节流窗口内的第二次命中：内存计数更新、但不写盘
        state.recordRuleHit(id, at: Date())
        state.persistence.waitForPendingWritesForTesting()
        XCTAssertEqual(state.ruleHitStats.hitCount(for: id), 2)
        XCTAssertEqual(makeState().ruleHitStats.hitCount(for: id), 1, "节流窗口内不应重复写盘")

        // 轮询循环的兜底补写路径：把最后的脏数据落掉
        state.ruleHitStatsSaveInterval = 0
        state.flushRuleHitStatsIfNeeded()
        state.persistence.waitForPendingWritesForTesting()
        XCTAssertEqual(makeState().ruleHitStats.hitCount(for: id), 2)
    }
}
