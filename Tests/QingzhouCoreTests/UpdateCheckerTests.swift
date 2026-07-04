import XCTest
@testable import QingzhouCore

/// App 内更新提醒的纯逻辑测试：语义化版本比较 + 是否该提示。
final class UpdateCheckerTests: XCTestCase {

    // MARK: - compareVersions

    /// 头号坑：不能按字符串比大小 —— "1.10.0" 必须 > "1.2.0"。
    func testNumericSegmentComparisonNotLexicographic() {
        XCTAssertEqual(UpdateChecker.compareVersions("1.2.0", "1.10.0"), .orderedAscending)
        XCTAssertEqual(UpdateChecker.compareVersions("1.10.0", "1.2.0"), .orderedDescending)
        XCTAssertEqual(UpdateChecker.compareVersions("1.9.0", "1.10.0"), .orderedAscending)
    }

    func testEqualVersions() {
        XCTAssertEqual(UpdateChecker.compareVersions("1.2.3", "1.2.3"), .orderedSame)
        XCTAssertEqual(UpdateChecker.compareVersions("2.0.0", "2.0.0"), .orderedSame)
    }

    func testBasicOrdering() {
        XCTAssertEqual(UpdateChecker.compareVersions("2.0.0", "1.9.9"), .orderedDescending)
        XCTAssertEqual(UpdateChecker.compareVersions("1.0.1", "1.0.0"), .orderedDescending)
        XCTAssertEqual(UpdateChecker.compareVersions("1.0.0", "1.0.1"), .orderedAscending)
    }

    /// 段数不等：短的一方缺失段补 0（"1.2" == "1.2.0"）。
    func testUnequalSegmentCounts() {
        XCTAssertEqual(UpdateChecker.compareVersions("1.2", "1.2.0"), .orderedSame)
        XCTAssertEqual(UpdateChecker.compareVersions("1.2.0", "1.2"), .orderedSame)
        XCTAssertEqual(UpdateChecker.compareVersions("1.2.1", "1.2"), .orderedDescending)
        XCTAssertEqual(UpdateChecker.compareVersions("1", "1.0.0.0"), .orderedSame)
        XCTAssertEqual(UpdateChecker.compareVersions("1.3", "1.2.9"), .orderedDescending)
    }

    /// 前导零按数值处理（"1.02" == "1.2"）。
    func testLeadingZeros() {
        XCTAssertEqual(UpdateChecker.compareVersions("1.02.0", "1.2.0"), .orderedSame)
        XCTAssertEqual(UpdateChecker.compareVersions("1.007", "1.7"), .orderedSame)
        XCTAssertEqual(UpdateChecker.compareVersions("01.0.0", "1.0.0"), .orderedSame)
    }

    /// 非法 / 非数字输入兜底为 0，绝不 crash。
    func testInvalidInputFallsBackToZero() {
        XCTAssertEqual(UpdateChecker.compareVersions("1.2.0-beta", "1.2.0"), .orderedSame)
        XCTAssertEqual(UpdateChecker.compareVersions("1.2.1-beta", "1.2.0"), .orderedDescending)
        XCTAssertEqual(UpdateChecker.compareVersions("abc", "1.0.0"), .orderedAscending)
        XCTAssertEqual(UpdateChecker.compareVersions("", ""), .orderedSame)
        XCTAssertEqual(UpdateChecker.compareVersions("", "0.0.0"), .orderedSame)
        XCTAssertEqual(UpdateChecker.compareVersions("1.0.0", ""), .orderedDescending)
        // 空段 / 尾随点也不能崩
        XCTAssertEqual(UpdateChecker.compareVersions("1..0", "1.0.0"), .orderedSame)
        XCTAssertEqual(UpdateChecker.compareVersions("  1.2.0  ", "1.2.0"), .orderedSame)
    }

    // MARK: - shouldPrompt

    /// 无结果（未上架 / 查询失败，latest = nil）→ 不提示。
    func testNilLatestDoesNotPrompt() {
        XCTAssertFalse(UpdateChecker.shouldPrompt(latest: nil, current: "1.0.0", ignored: ""))
        XCTAssertFalse(UpdateChecker.shouldPrompt(latest: "", current: "1.0.0", ignored: ""))
    }

    /// 相等（已是最新）→ 不提示。
    func testEqualVersionDoesNotPrompt() {
        XCTAssertFalse(UpdateChecker.shouldPrompt(latest: "1.2.0", current: "1.2.0", ignored: ""))
    }

    /// 当前版本更高（本地跑的是未发布版）→ 不提示。
    func testCurrentNewerDoesNotPrompt() {
        XCTAssertFalse(UpdateChecker.shouldPrompt(latest: "1.2.0", current: "1.3.0", ignored: ""))
    }

    /// 有更新版本、没忽略过 → 提示。
    func testNewerVersionPrompts() {
        XCTAssertTrue(UpdateChecker.shouldPrompt(latest: "1.3.0", current: "1.2.0", ignored: ""))
        XCTAssertTrue(UpdateChecker.shouldPrompt(latest: "1.10.0", current: "1.2.0", ignored: ""))
    }

    /// 已忽略该版本 → 同一版本不再提示。
    func testIgnoredVersionDoesNotPrompt() {
        XCTAssertFalse(UpdateChecker.shouldPrompt(latest: "1.3.0", current: "1.2.0", ignored: "1.3.0"))
    }

    /// 忽略了旧版本后，出了更新的版本 → 再次提示。
    func testNewerThanIgnoredPromptsAgain() {
        XCTAssertTrue(UpdateChecker.shouldPrompt(latest: "1.4.0", current: "1.2.0", ignored: "1.3.0"))
    }

    /// latest 不比 ignored 更新（相等或更旧）→ 不提示。
    func testNotNewerThanIgnoredDoesNotPrompt() {
        XCTAssertFalse(UpdateChecker.shouldPrompt(latest: "1.3.0", current: "1.2.0", ignored: "1.3.0"))
        XCTAssertFalse(UpdateChecker.shouldPrompt(latest: "1.2.5", current: "1.2.0", ignored: "1.3.0"))
    }
}
