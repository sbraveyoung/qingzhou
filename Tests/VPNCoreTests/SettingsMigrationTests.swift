import XCTest
@testable import VPNCore

/// Settings 的 Codable 解码必须容忍旧版本（字段缺失），给默认值。
/// 这点对持久化是刚性需求：用户升级 app 时不能因为新字段把旧 JSON 全报废。
final class SettingsMigrationTests: XCTestCase {

    private func decode(_ json: String) throws -> Settings {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(Settings.self, from: data)
    }

    func testDecodeEmptyJSONUsesDefaults() throws {
        let s = try decode("{}")
        XCTAssertEqual(s.proxyMode, .rule)
        XCTAssertEqual(s.httpPort, 7890)
        XCTAssertEqual(s.subscriptionRefreshIntervalSeconds, 3600)
        XCTAssertEqual(s.theme, .system)
    }

    func testDecodeOldSnapshotWithoutNewFields() throws {
        // 模拟阶段 1.5 之前的 settings.json：没有 subscriptionRefreshIntervalSeconds
        let json = """
        {
          "proxyMode": "global",
          "autoSelectTrigger": "off",
          "autoSelectIntervalSeconds": 600,
          "nodeSortOrder": "name",
          "systemProxyEnabled": false,
          "launchAtLogin": false,
          "httpPort": 8888,
          "socksPort": 1080,
          "logLevel": "WARN",
          "theme": "dark",
          "language": "en"
        }
        """
        let s = try decode(json)
        XCTAssertEqual(s.proxyMode, .global)
        XCTAssertEqual(s.httpPort, 8888)
        XCTAssertEqual(s.theme, .dark)
        XCTAssertEqual(s.language, .en)
        // 新字段拿默认值，不应崩
        XCTAssertEqual(s.subscriptionRefreshIntervalSeconds, 3600)
    }

    func testRoundtripPreservesNewField() throws {
        var s = Settings()
        s.subscriptionRefreshIntervalSeconds = 900
        let data = try JSONEncoder().encode(s)
        let reloaded = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(reloaded.subscriptionRefreshIntervalSeconds, 900)
    }

    func testZeroIntervalMeansOff() throws {
        var s = Settings()
        s.subscriptionRefreshIntervalSeconds = 0
        XCTAssertEqual(s.subscriptionRefreshIntervalSeconds, 0)
    }
}
