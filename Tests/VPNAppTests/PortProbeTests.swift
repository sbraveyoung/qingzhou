import XCTest
import Darwin
@testable import VPNApp

final class PortProbeTests: XCTestCase {

    /// 一个大概率空闲的高位端口应被判为可用。
    func testHighPortIsAvailable() {
        // 选个不太可能被占的高位端口；偶发被占就换一个重试几次
        let candidates = [54321, 54322, 54323, 54324, 54325]
        XCTAssertTrue(candidates.contains { PortProbe.isAvailable($0) },
                      "至少一个高位端口应当空闲可绑定")
    }

    /// 非法端口号判为不可用。
    func testInvalidPortIsUnavailable() {
        XCTAssertFalse(PortProbe.isAvailable(0))
        XCTAssertFalse(PortProbe.isAvailable(70000))
        XCTAssertFalse(PortProbe.isAvailable(-1))
    }

    /// 自己 bind+listen 占住一个端口后，应被判为不可用。
    func testOccupiedPortIsDetected() throws {
        // 找一个空闲端口先占住
        let port = (54330...54380).first { PortProbe.isAvailable($0) }
        guard let port else {
            throw XCTSkip("找不到空闲端口做测试")
        }

        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port)).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(bound, 0, "测试自身应能先占住端口")
        XCTAssertEqual(listen(fd, 1), 0)

        // 现在这个端口被占，PortProbe 应当判为不可用
        XCTAssertFalse(PortProbe.isAvailable(port))
        XCTAssertEqual(PortProbe.firstOccupied(among: [port]), port)
    }
}
