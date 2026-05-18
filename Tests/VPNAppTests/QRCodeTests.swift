import XCTest
@testable import VPNApp

final class QRCodeTests: XCTestCase {
    func testGenerateShortString() {
        let img = QRCode.generate(from: "trojan://pw@example.com:443#hk", size: 200)
        XCTAssertNotNil(img)
    }

    func testGenerateLongString() {
        // 几百字节内仍应能生成
        let big = String(repeating: "abc123", count: 50)
        let img = QRCode.generate(from: big, size: 240)
        XCTAssertNotNil(img)
    }

    func testGenerateEmpty() {
        // 空字符串 QR 在 CIFilter 里实际能生成（一个空 payload 的 QR）；
        // 这里只要求不 crash 且返回 non-nil。
        let img = QRCode.generate(from: "", size: 100)
        XCTAssertNotNil(img)
    }
}
