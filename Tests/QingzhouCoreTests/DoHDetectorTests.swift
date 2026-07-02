import XCTest
@testable import QingzhouCore

/// DoHDetector：连接页 / 域名分析的「浏览器可能在用加密 DNS」提示的触发判定 ——
/// 最近连接里裸 IP 占比 >50% 且 >20 条时，说明 FakeDNS 大概率被浏览器 DoH 绕过了。
final class DoHDetectorTests: XCTestCase {

    private func conn(_ host: String) -> Connection {
        Connection(targetHost: host, sourceAddress: "127.0.0.1:1",
                   targetAddress: "\(host):443", type: .https, route: "PROXY", matchedRule: "")
    }

    func testTriggersAboveBothThresholds() {
        XCTAssertTrue(DoHDetector.isLikelyDoH(bareIPCount: 21, totalCount: 40))   // 52.5%、21 条
        XCTAssertTrue(DoHDetector.isLikelyDoH(bareIPCount: 100, totalCount: 120))
    }

    func testCountThresholdIsStrict() {
        // 恰好 20 条不触发（>20 的语义）：小样本占比波动大，宁可保守
        XCTAssertFalse(DoHDetector.isLikelyDoH(bareIPCount: 20, totalCount: 22))
    }

    func testShareThresholdIsStrict() {
        XCTAssertFalse(DoHDetector.isLikelyDoH(bareIPCount: 30, totalCount: 60))  // 恰好 50%
        XCTAssertFalse(DoHDetector.isLikelyDoH(bareIPCount: 21, totalCount: 50))  // 42%
    }

    func testEmptyAndDegenerateInputs() {
        XCTAssertFalse(DoHDetector.isLikelyDoH(bareIPCount: 0, totalCount: 0))
        XCTAssertFalse(DoHDetector.isLikelyDoH(bareIPCount: 0, totalCount: 100))
    }

    func testConnectionsOverloadCountsBareIPs() {
        // 25 条裸 IP + 5 条域名 → 83%、25 条 → 触发
        var conns = (0..<25).map { conn("142.250.66.\($0 + 1)") }
        conns += (0..<5).map { _ in conn("example.com") }
        XCTAssertTrue(DoHDetector.isLikelyDoH(connections: conns))

        // 域名占多数 → 不触发
        var mostlyDomains = (0..<25).map { _ in conn("example.com") }
        mostlyDomains += (0..<21).map { conn("10.0.0.\($0 + 1)") }
        XCTAssertFalse(DoHDetector.isLikelyDoH(connections: mostlyDomains))
    }
}
