import XCTest
@testable import VPNCore

final class AccessLogParserTests: XCTestCase {

    func testParsesTypicalProxyLineWithTimestamp() {
        let line = "2026/07/01 12:00:00 from 127.0.0.1:54321 accepted tcp:www.google.com:443 [tun-in -> proxy]"
        let e = AccessLogParser.parseLine(line)
        XCTAssertEqual(e?.sourceAddress, "127.0.0.1:54321")
        XCTAssertEqual(e?.network, "tcp")
        XCTAssertEqual(e?.targetHost, "www.google.com")
        XCTAssertEqual(e?.targetPort, 443)
        XCTAssertEqual(e?.inboundTag, "tun-in")
        XCTAssertEqual(e?.outboundTag, "proxy")
        XCTAssertEqual(e?.accepted, true)
    }

    func testParsesDirectUDPLine() {
        let e = AccessLogParser.parseLine("from 10.0.0.2:5000 accepted udp:223.5.5.5:53 [tun-in -> direct]")
        XCTAssertEqual(e?.network, "udp")
        XCTAssertEqual(e?.targetHost, "223.5.5.5")
        XCTAssertEqual(e?.targetPort, 53)
        XCTAssertEqual(e?.outboundTag, "direct")
    }

    func testParsesRejectedLine() {
        let e = AccessLogParser.parseLine("from 127.0.0.1:1 rejected tcp:ad.doubleclick.net:443 [tun-in -> reject]")
        XCTAssertEqual(e?.accepted, false)
        XCTAssertEqual(e?.targetHost, "ad.doubleclick.net")
        XCTAssertEqual(e?.outboundTag, "reject")
    }

    func testStripsSourceNetworkPrefixAndIPv6Brackets() {
        let e = AccessLogParser.parseLine("from tcp:1.2.3.4:6000 accepted tcp:[2001:db8::1]:443 [tun-in -> proxy]")
        XCTAssertEqual(e?.sourceAddress, "1.2.3.4:6000", "source 的 net: 前缀要剥掉")
        XCTAssertEqual(e?.targetHost, "2001:db8::1", "IPv6 外层方括号要去掉")
        XCTAssertEqual(e?.targetPort, 443)
    }

    func testLineWithoutDetourStillParses() {
        let e = AccessLogParser.parseLine("from 127.0.0.1:5 accepted tcp:example.com:8080")
        XCTAssertEqual(e?.targetHost, "example.com")
        XCTAssertEqual(e?.targetPort, 8080)
        XCTAssertEqual(e?.outboundTag, "")
    }

    func testNonAccessLineReturnsNil() {
        XCTAssertNil(AccessLogParser.parseLine("2026/07/01 12:00:00 [Warning] some unrelated log"))
        XCTAssertNil(AccessLogParser.parseLine(""))
    }

    func testParseSkipsUnparseableLines() {
        let text = """
        from 127.0.0.1:1 accepted tcp:a.com:443 [tun-in -> proxy]
        garbage line
        from 127.0.0.1:2 accepted tcp:b.com:443 [tun-in -> direct]
        """
        let entries = AccessLogParser.parse(text)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.targetHost), ["a.com", "b.com"])
    }

    func testMakeConnectionMapsOutboundToRoute() {
        let proxy = AccessLogParser.parseLine("from 127.0.0.1:1 accepted tcp:x.com:443 [tun-in -> proxy]")!
        XCTAssertEqual(proxy.makeConnection(proxyDisplayName: "日本-TY-1").route, "日本-TY-1")
        XCTAssertEqual(proxy.makeConnection(proxyDisplayName: "日本-TY-1").type, .https)

        let direct = AccessLogParser.parseLine("from 127.0.0.1:1 accepted udp:y.com:53 [tun-in -> direct]")!
        XCTAssertEqual(direct.makeConnection(proxyDisplayName: "日本-TY-1").route, "DIRECT")
        XCTAssertEqual(direct.makeConnection(proxyDisplayName: nil).type, .udp)

        let reject = AccessLogParser.parseLine("from 127.0.0.1:1 rejected tcp:z.com:443 [tun-in -> reject]")!
        XCTAssertEqual(reject.makeConnection(proxyDisplayName: "日本-TY-1").route, "REJECT")
    }
}
