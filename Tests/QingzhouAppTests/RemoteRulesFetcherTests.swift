import XCTest
import QingzhouCore
import QingzhouSubscription
@testable import QingzhouApp

final class RemoteRulesFetcherTests: XCTestCase {

    struct StubClient: HTTPClient {
        let body: String
        let headers: [String: String]
        func get(_ url: URL) async throws -> (Data, [String: String]) {
            (Data(body.utf8), headers)
        }
    }

    func testFetchParsesRulesAndIgnoresComments() async throws {
        let body = """
        # whitelist.conf
        DOMAIN-SUFFIX,google.com,PROXY
        DOMAIN-KEYWORD,apple,DIRECT
        IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
        FINAL,PROXY
        invalid_garbage_line
        """
        let fetcher = RemoteRulesFetcher(client: StubClient(body: body, headers: [:]))
        let rules = try await fetcher.fetch(URL(string: "https://example.com/r.conf")!)
        XCTAssertEqual(rules.count, 4)
        XCTAssertEqual(rules.first?.type, .domainSuffix)
        XCTAssertEqual(rules.last?.type, .final)
    }

    func testFetchHandlesEmptyBody() async throws {
        let fetcher = RemoteRulesFetcher(client: StubClient(body: "", headers: [:]))
        let rules = try await fetcher.fetch(URL(string: "https://example.com")!)
        XCTAssertTrue(rules.isEmpty)
    }

    func testFetchPropagatesError() async {
        struct FailingClient: HTTPClient {
            func get(_ url: URL) async throws -> (Data, [String: String]) {
                throw URLError(.cannotConnectToHost)
            }
        }
        let fetcher = RemoteRulesFetcher(client: FailingClient())
        do {
            _ = try await fetcher.fetch(URL(string: "https://example.com")!)
            XCTFail("expected error")
        } catch { /* ok */ }
    }
}
