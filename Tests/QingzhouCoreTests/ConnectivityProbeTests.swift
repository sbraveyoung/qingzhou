import XCTest
@testable import QingzhouCore

final class ConnectivityProbeTests: XCTestCase {
    func testDefaultsToBuiltinListWhenNoPreference() {
        let targets = ConnectivityProbe.sentinelTargets(preferred: nil)
        XCTAssertEqual(targets, ConnectivityProbe.presets.map(\.url))
        XCTAssertEqual(ConnectivityProbe.sentinelTargets(preferred: ""), targets)
    }

    func testPreferredMovesToFrontWithoutDuplication() {
        let google = "https://www.google.com/generate_204"
        let targets = ConnectivityProbe.sentinelTargets(preferred: google)
        XCTAssertEqual(targets.first, google, "用户指定的目标应排最前")
        XCTAssertEqual(targets.filter { $0 == google }.count, 1, "预设里已有的目标不该重复出现")
        // 其余内置目标仍在，保证「单点被 reset」时还有候选兜底
        XCTAssertTrue(targets.contains("https://cp.cloudflare.com/generate_204"))
        XCTAssertGreaterThan(targets.count, 1)
    }

    func testCustomDomainPrependedAndBuiltinKept() {
        let custom = "https://example.com/health"
        let targets = ConnectivityProbe.sentinelTargets(preferred: custom)
        XCTAssertEqual(targets.first, custom)
        XCTAssertEqual(targets.count, ConnectivityProbe.presets.count + 1)
    }

    func testInvalidPreferredFallsBackToBuiltin() {
        // 空格 / 非 URL：URL(string:) 仍可能成功，这里用明显非法的空串已在别处覆盖；
        // 保证多目标始终非空、Google 不是唯一探测点（旧实现的坑）
        let targets = ConnectivityProbe.sentinelTargets(preferred: "")
        XCTAssertFalse(targets.isEmpty)
        XCTAssertNotEqual(targets, ["https://www.google.com/generate_204"], "绝不能退化成 Google 单点")
    }

    func testDefaultProxiedTargetIsCloudflare() {
        XCTAssertTrue(ConnectivityProbe.defaultProxiedTarget.contains("cloudflare"))
    }
}
