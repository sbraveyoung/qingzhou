import XCTest
import QingzhouCore
@testable import QingzhouSubscription

final class QingzhouSubscriptionTests: XCTestCase {

    // MARK: - Userinfo header

    func testParseUserinfoHeaderFull() {
        let info = SubscriptionUserInfo.parse("upload=100; download=200; total=1000; expire=1730000000")
        XCTAssertEqual(info.upload, 100)
        XCTAssertEqual(info.download, 200)
        XCTAssertEqual(info.total, 1000)
        XCTAssertEqual(info.usedBytes, 300)
        XCTAssertEqual(info.expire, Date(timeIntervalSince1970: 1730000000))
    }

    func testParseUserinfoHeaderPartial() {
        let info = SubscriptionUserInfo.parse("upload=50, total=500")
        XCTAssertEqual(info.upload, 50)
        XCTAssertNil(info.download)
        XCTAssertEqual(info.total, 500)
        XCTAssertEqual(info.usedBytes, 50)
        XCTAssertNil(info.expire)
    }

    func testParseUserinfoHeaderIgnoresUnknown() {
        let info = SubscriptionUserInfo.parse("foo=bar; total=100; baz=qux")
        XCTAssertEqual(info.total, 100)
    }

    // MARK: - SubscriptionParser

    func testParsePlainLinks() {
        let body = """
        trojan://pw@a.com:443#A
        ss://YWVzLTEyOC1nY206cHc=@b.com:8388#B
        """
        let payload = SubscriptionParser.parse(body: body)
        XCTAssertEqual(payload.nodes.count, 2)
        XCTAssertEqual(payload.nodes[0].protocolType, .trojan)
        XCTAssertEqual(payload.nodes[1].protocolType, .shadowsocks)
    }

    func testParseBase64Encoded() {
        let inner = "trojan://pw@a.com:443#A\nhy2://pw@b.com:443#B"
        let b64 = Data(inner.utf8).base64EncodedString()
        let payload = SubscriptionParser.parse(body: b64)
        XCTAssertEqual(payload.nodes.count, 2)
    }

    func testParseBase64WithoutPadding() {
        // 模拟订阅源去掉 = padding
        let inner = "trojan://pw@a.com:443#A"
        var b64 = Data(inner.utf8).base64EncodedString()
        while b64.hasSuffix("=") { b64.removeLast() }
        let payload = SubscriptionParser.parse(body: b64)
        XCTAssertEqual(payload.nodes.count, 1)
    }

    func testParseWithUserinfoHeader() {
        let body = "trojan://pw@a.com:443#A"
        let payload = SubscriptionParser.parse(
            body: body,
            userInfoHeader: "upload=10; download=20; total=100"
        )
        XCTAssertEqual(payload.nodes.count, 1)
        XCTAssertEqual(payload.userInfo?.usedBytes, 30)
    }

    func testParseCollectsErrors() {
        let body = "trojan://pw@a.com:443#A\nblahblahblah"
        let payload = SubscriptionParser.parse(body: body)
        XCTAssertEqual(payload.nodes.count, 1)
        XCTAssertEqual(payload.failedLines.count, 1)
    }

    // MARK: - SubscriptionFetcher with mock HTTPClient

    struct MockHTTPClient: HTTPClient {
        let body: String
        let headers: [String: String]
        func get(_ url: URL) async throws -> (Data, [String: String]) {
            (Data(body.utf8), headers)
        }
    }

    func testFetcherUpdatesSubscriptionMeta() async throws {
        let body = "trojan://pw@a.com:443#A\ntrojan://pw@b.com:443#B"
        let client = MockHTTPClient(
            body: body,
            headers: ["subscription-userinfo": "upload=1; download=2; total=100; expire=1730000000"]
        )
        let fetcher = SubscriptionFetcher(client: client)
        let sub = Subscription(name: "S", url: URL(string: "https://example.com/sub")!)
        let (updated, payload) = try await fetcher.refresh(sub)
        XCTAssertEqual(updated.nodeCount, 2)
        XCTAssertNotNil(updated.lastUpdatedAt)
        XCTAssertEqual(updated.usedBytes, 3)
        XCTAssertEqual(updated.totalBytes, 100)
        XCTAssertEqual(payload.nodes.count, 2)
        // 节点应该被打上订阅 id
        XCTAssertEqual(payload.nodes[0].subscriptionId, updated.id)
        XCTAssertEqual(payload.nodes[1].subscriptionId, updated.id)
    }
}
