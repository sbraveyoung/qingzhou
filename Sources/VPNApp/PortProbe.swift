import Foundation
import Darwin

/// 检测本地 TCP 端口能否绑定（即是否被别的进程占用）。
///
/// 用途：macOS 开启本地 SOCKS/HTTP 代理前先探一下 127.0.0.1:port 是否空闲。
/// xray-core 在 Extension 里启动时如果端口被占会失败，但报错信息晦涩；在主 App 这边
/// 先探一次能给用户清晰的「端口被占用」提示，且不用白白把整条隧道拉起来再失败。
///
/// 原理：`bind()` 到 127.0.0.1:port，能绑上就是空闲（随即 close 释放），
/// 绑不上（EADDRINUSE）就是被占。带 SO_REUSEADDR 关闭，确保探测真实占用而非 TIME_WAIT 残留。
enum PortProbe {

    /// true = 端口空闲可用；false = 被占用 / 不可绑定。
    static func isAvailable(_ port: Int, host: String = "127.0.0.1") -> Bool {
        guard (1...65535).contains(port) else { return false }

        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        // 故意不设 SO_REUSEADDR —— 我们要探测"真的有人在 LISTEN 这个端口"，
        // SO_REUSEADDR 会让 bind 在某些占用情况下误判为成功。

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port)).bigEndian
        addr.sin_addr.s_addr = inet_addr(host)

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return bindResult == 0
    }

    /// 返回第一个被占用的端口（用于报错文案）；都空闲返回 nil。
    static func firstOccupied(among ports: [Int]) -> Int? {
        ports.first { !isAvailable($0) }
    }
}
