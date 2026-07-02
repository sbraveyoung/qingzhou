import XCTest
@testable import QingzhouCore

/// RuleHitStats：自定义规则的命中计数（按天滚动、保留 30 天、只存本地）。
/// 规则页据此显示「近 30 天命中 N 次」，长期零命中的给「可考虑删除」弱提示。
final class RuleHitStatsTests: XCTestCase {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()

    private let day0 = Date(timeIntervalSince1970: 1_750_000_000)

    func testRecordAccumulatesPerRule() {
        let id = UUID(), other = UUID()
        var s = RuleHitStats(trackingSince: day0)
        s.recordHit(id, at: day0, calendar: cal)
        s.recordHit(id, at: day0.addingTimeInterval(60), calendar: cal)
        s.recordHit(other, at: day0, calendar: cal)
        XCTAssertEqual(s.hitCount(for: id), 2)
        XCTAssertEqual(s.hitCount(for: other), 1)
        XCTAssertEqual(s.hitCount(for: UUID()), 0, "没记录过的规则计 0")
    }

    func testHitCountSumsAcrossDays() {
        let id = UUID()
        var s = RuleHitStats(trackingSince: day0)
        s.recordHit(id, at: day0, calendar: cal)
        s.recordHit(id, at: day0.addingTimeInterval(86_400 * 3), calendar: cal)
        XCTAssertEqual(s.hitCount(for: id), 2)
    }

    func testPruneDropsCountsOlderThanKeepDays() {
        let id = UUID()
        var s = RuleHitStats(trackingSince: day0)
        s.recordHit(id, at: day0, calendar: cal)
        let later = day0.addingTimeInterval(86_400 * 40)
        s.recordHit(id, at: later, calendar: cal)
        s.prune(keepDays: 30, now: later, calendar: cal)
        XCTAssertEqual(s.hitCount(for: id), 1, "40 天前的命中应被滚动清理")
    }

    func testIdleCandidateRequiresMatureTrackingAndZeroHits() {
        let id = UUID()
        var s = RuleHitStats(trackingSince: day0)

        // 刚开始跟踪（不足 7 天观察期）：零命中也不提示 —— 否则功能上线首日全部规则被误标
        XCTAssertFalse(s.isIdleCandidate(id, now: day0.addingTimeInterval(86_400 * 2), calendar: cal))

        // 观察期已满 + 零命中 → 提示
        let mature = day0.addingTimeInterval(86_400 * 10)
        XCTAssertTrue(s.isIdleCandidate(id, now: mature, calendar: cal))

        // 有命中 → 不提示
        s.recordHit(id, at: mature, calendar: cal)
        XCTAssertFalse(s.isIdleCandidate(id, now: mature, calendar: cal))
    }

    func testCodableRoundTrip() throws {
        let id = UUID()
        var s = RuleHitStats(trackingSince: day0)
        s.recordHit(id, at: day0, calendar: cal)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(RuleHitStats.self, from: data)
        XCTAssertEqual(back, s)
        XCTAssertEqual(back.hitCount(for: id), 1)
    }
}
