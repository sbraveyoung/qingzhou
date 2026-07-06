import XCTest
@testable import QingzhouCore

final class QingzhouCoreTests: XCTestCase {

    // MARK: - ProxyProtocol

    func testProxyProtocolFromScheme() {
        XCTAssertEqual(ProxyProtocol.from(scheme: "trojan"), .trojan)
        XCTAssertEqual(ProxyProtocol.from(scheme: "ss"), .shadowsocks)
        XCTAssertEqual(ProxyProtocol.from(scheme: "vmess"), .vmess)
        XCTAssertEqual(ProxyProtocol.from(scheme: "vless"), .vless)
        XCTAssertEqual(ProxyProtocol.from(scheme: "hysteria2"), .hysteria2)
        XCTAssertEqual(ProxyProtocol.from(scheme: "hy2"), .hysteria2)
        XCTAssertEqual(ProxyProtocol.from(scheme: "HY2"), .hysteria2)
        XCTAssertNil(ProxyProtocol.from(scheme: "wireguard"))
    }

    // MARK: - Node sorting

    func testNodesSortedByName() {
        let nodes = [
            Node(name: "BB", protocolType: .trojan, host: "h", port: 1),
            Node(name: "aa", protocolType: .trojan, host: "h", port: 1),
            Node(name: "Cc", protocolType: .trojan, host: "h", port: 1)
        ]
        let sorted = nodes.sorted(by: .name).map(\.name)
        XCTAssertEqual(sorted, ["aa", "BB", "Cc"])
    }

    func testNodesSortedByLatencyPutsNilLast() {
        let nodes = [
            Node(name: "n3", protocolType: .trojan, host: "h", port: 1, lastLatencyMs: nil),
            Node(name: "n1", protocolType: .trojan, host: "h", port: 1, lastLatencyMs: 100),
            Node(name: "n2", protocolType: .trojan, host: "h", port: 1, lastLatencyMs: 50)
        ]
        let sorted = nodes.sorted(by: .latency).map(\.name)
        XCTAssertEqual(sorted, ["n2", "n1", "n3"])
    }

    func testNodesSortedByLatencyTieBreaksByName() {
        let nodes = [
            Node(name: "B", protocolType: .trojan, host: "h", port: 1, lastLatencyMs: 50),
            Node(name: "A", protocolType: .trojan, host: "h", port: 1, lastLatencyMs: 50)
        ]
        let sorted = nodes.sorted(by: .latency).map(\.name)
        XCTAssertEqual(sorted, ["A", "B"])
    }

    func testIdentityFingerprintStableAcrossRefresh() {
        let a = Node(name: "old name", protocolType: .trojan, host: "h.com", port: 443, password: "pw")
        let b = Node(name: "new name", protocolType: .trojan, host: "h.com", port: 443, password: "pw")
        XCTAssertEqual(a.identityFingerprint, b.identityFingerprint)
    }

    // MARK: - Subscription

    func testSubscriptionUsageRatio() {
        let sub = Subscription(
            name: "S",
            url: URL(string: "https://x")!,
            usedBytes: 25,
            totalBytes: 100
        )
        XCTAssertEqual(sub.usageRatio, 0.25)
    }

    func testSubscriptionUsageRatioMissing() {
        let sub = Subscription(name: "S", url: URL(string: "https://x")!)
        XCTAssertNil(sub.usageRatio)
    }

    func testSubscriptionUsageRatioCapsAtOne() {
        let sub = Subscription(
            name: "S",
            url: URL(string: "https://x")!,
            usedBytes: 200,
            totalBytes: 100
        )
        XCTAssertEqual(sub.usageRatio, 1.0)
    }

    // MARK: - Rule

    func testRuleLineForm() {
        let r = Rule(type: .domainSuffix, value: "google.com", target: .proxy)
        XCTAssertEqual(r.lineForm, "DOMAIN-SUFFIX,google.com,PROXY")
    }

    func testRuleLineFormFinal() {
        let r = Rule(type: .final, value: "", target: .direct)
        XCTAssertEqual(r.lineForm, "FINAL,DIRECT")
    }

    // MARK: - Connection

    func testConnectionIsActive() {
        let c = Connection(targetHost: "h", sourceAddress: "1", targetAddress: "2", type: .https, route: "r", matchedRule: "x")
        XCTAssertTrue(c.isActive)
        var closed = c
        closed.closedAt = Date()
        XCTAssertFalse(closed.isActive)
    }

    func testConnectionTargetPortAndDNS() {
        // 常规 IPv4 DNS 查询：端口 53 → isDNSQuery
        let dns = Connection(targetHost: "8.8.8.8", sourceAddress: "10.0.0.1:5",
                             targetAddress: "8.8.8.8:53", type: .udp, route: "DIRECT", matchedRule: "")
        XCTAssertEqual(dns.targetPort, 53)
        XCTAssertTrue(dns.isDNSQuery)
        // 普通 HTTPS：443 → 不是 DNS
        let https = Connection(targetHost: "example.com", sourceAddress: "10.0.0.1:6",
                               targetAddress: "example.com:443", type: .https, route: "PROXY", matchedRule: "")
        XCTAssertEqual(https.targetPort, 443)
        XCTAssertFalse(https.isDNSQuery)
        // IPv6 目标：端口靠已知 targetHost 前缀剥出，不被地址里的冒号干扰
        let v6 = Connection(targetHost: "2606:4700:4700::1111", sourceAddress: "[::1]:7",
                            targetAddress: "2606:4700:4700::1111:53", type: .udp, route: "DIRECT", matchedRule: "")
        XCTAssertEqual(v6.targetPort, 53)
        XCTAssertTrue(v6.isDNSQuery)
        // 域名里恰好含 :53 的假阳性防护：host 前缀对不上 → nil，不误判
        let tricky = Connection(targetHost: "a.com", sourceAddress: "10.0.0.1:8",
                                targetAddress: "b.com:53", type: .tcp, route: "PROXY", matchedRule: "")
        XCTAssertNil(tricky.targetPort)
        XCTAssertFalse(tricky.isDNSQuery)
    }

    // MARK: - ByteFormatter

    func testByteFormatter() {
        XCTAssertEqual(ByteFormatter.format(0), "0 B")
        XCTAssertEqual(ByteFormatter.format(512), "512 B")
        XCTAssertEqual(ByteFormatter.format(1024), "1.00 KB")
        XCTAssertEqual(ByteFormatter.format(1024 * 1024), "1.00 MB")
        XCTAssertEqual(ByteFormatter.format(-5), "0 B")
    }
}
