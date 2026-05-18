import XCTest
@testable import VPNLogging

final class VPNLoggingTests: XCTestCase {

    func testLogLevelOrdering() {
        XCTAssertTrue(LogLevel.debug < .info)
        XCTAssertTrue(LogLevel.info < .warn)
        XCTAssertTrue(LogLevel.warn < .error)
        XCTAssertTrue(LogLevel.all < .debug)
    }

    func testLoggerRespectsMinimumLevel() {
        let logger = Logger(capacity: 100, minimumLevel: .warn)
        logger.debug("hidden")
        logger.info("hidden")
        logger.warn("shown")
        logger.error("shown")
        let entries = logger.snapshot()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.level), [.warn, .error])
    }

    func testLoggerRingBufferEvictsOldest() {
        let logger = Logger(capacity: 3, minimumLevel: .debug)
        logger.info("1")
        logger.info("2")
        logger.info("3")
        logger.info("4")
        let entries = logger.snapshot()
        XCTAssertEqual(entries.map(\.message), ["2", "3", "4"])
    }

    func testLoggerSearchByKeyword() {
        let logger = Logger(capacity: 100, minimumLevel: .debug)
        logger.info("connection established", category: "net")
        logger.info("user clicked button", category: "ui")
        logger.error("connection lost", category: "net")
        let results = logger.search(level: .all, keyword: "connection")
        XCTAssertEqual(results.count, 2)
    }

    func testLoggerSearchByLevel() {
        let logger = Logger(capacity: 100, minimumLevel: .debug)
        logger.debug("d")
        logger.info("i")
        logger.error("e")
        let results = logger.search(level: .warn)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].level, .error)
    }

    func testLoggerSubscribeFiresCallback() {
        let logger = Logger(capacity: 100, minimumLevel: .debug)
        let exp = expectation(description: "callback")
        exp.expectedFulfillmentCount = 2
        let token = logger.subscribe { _ in exp.fulfill() }
        logger.info("a")
        logger.info("b")
        wait(for: [exp], timeout: 1.0)
        logger.unsubscribe(token)
        logger.info("c")   // 不应再触发
    }

    func testLoggerClear() {
        let logger = Logger(capacity: 100, minimumLevel: .debug)
        logger.info("x")
        logger.info("y")
        logger.clear()
        XCTAssertTrue(logger.snapshot().isEmpty)
    }

    func testLoggerFileSinkWritesLines() throws {
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vpn-test-log-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let logger = Logger(capacity: 100, minimumLevel: .debug)
        try logger.enableFileSink(at: tmpURL)
        logger.info("hello world", category: "test")
        logger.error("boom", category: "test")
        logger.disableFileSink()

        let content = try String(contentsOf: tmpURL, encoding: .utf8)
        XCTAssertTrue(content.contains("hello world"))
        XCTAssertTrue(content.contains("boom"))
        XCTAssertTrue(content.contains("[INFO]"))
        XCTAssertTrue(content.contains("[ERROR]"))
    }
}
