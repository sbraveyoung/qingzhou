#if os(macOS)
import Foundation
import ServiceManagement
import VPNLogging

/// 包装 macOS 系统级集成。`MacSystemServices` 是 namespace，里面的 API 都是静态的。
public enum MacSystemServices {

    // MARK: - 开机自启

    /// 返回当前主 app 是否注册为登录项。
    public static func isLoginItemEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 注册 / 注销主 app 的开机自启。
    /// - Returns: 操作后的最终状态（true 表示已启用）。
    @discardableResult
    public static func setLoginItem(_ enabled: Bool, logger: Logger? = nil) -> Bool {
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled {
                try service.register()
            } else if !enabled, service.status == .enabled {
                try service.unregister()
            }
        } catch {
            logger?.error("Toggle login item failed: \(error)", category: "system")
        }
        return service.status == .enabled
    }

    // MARK: - 系统代理

    /// 给当前所有 Wi-Fi / Ethernet 网络服务设置 HTTP / HTTPS / SOCKS 代理为 127.0.0.1:<port>。
    ///
    /// 用 `/usr/sbin/networksetup`，需要管理员权限 —— 这里**不**自动 sudo，调用方失败要给用户提示。
    /// 在 App Sandbox 模式下这个 API 不可用（会报权限错误）；要让它能用，需要在 entitlements
    /// 关闭 sandbox 或加 `com.apple.security.temporary-exception.shared-preference.read-write` 等。
    public static func setSystemProxy(httpPort: Int, socksPort: Int, enabled: Bool, logger: Logger? = nil) -> Bool {
        let services = listNetworkServices()
        guard !services.isEmpty else {
            logger?.warn("No network services available for proxy toggle", category: "system")
            return false
        }
        var allOK = true
        for service in services {
            for cmd in proxyCommands(service: service, httpPort: httpPort, socksPort: socksPort, enabled: enabled) {
                if !runNetworkSetup(arguments: cmd, logger: logger) {
                    allOK = false
                }
            }
        }
        return allOK
    }

    private static func listNetworkServices() -> [String] {
        let output = runCapturing(arguments: ["-listallnetworkservices"]) ?? ""
        let lines = output.split(separator: "\n").map(String.init)
        // 第 1 行是说明文字，跳过；星号前缀表示已禁用，去掉
        return lines.dropFirst().compactMap { line in
            var s = line
            if s.hasPrefix("*") { s.removeFirst() }
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private static func proxyCommands(service: String, httpPort: Int, socksPort: Int, enabled: Bool) -> [[String]] {
        if enabled {
            return [
                ["-setwebproxy", service, "127.0.0.1", "\(httpPort)"],
                ["-setsecurewebproxy", service, "127.0.0.1", "\(httpPort)"],
                ["-setsocksfirewallproxy", service, "127.0.0.1", "\(socksPort)"]
            ]
        } else {
            return [
                ["-setwebproxystate", service, "off"],
                ["-setsecurewebproxystate", service, "off"],
                ["-setsocksfirewallproxystate", service, "off"]
            ]
        }
    }

    @discardableResult
    private static func runNetworkSetup(arguments: [String], logger: Logger?) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = arguments
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus != 0 {
                logger?.warn("networksetup \(arguments.joined(separator: " ")) exit \(task.terminationStatus)", category: "system")
                return false
            }
            return true
        } catch {
            logger?.error("networksetup \(arguments.joined(separator: " ")) failed: \(error)", category: "system")
            return false
        }
    }

    private static func runCapturing(arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

extension AppState {
    /// 应用 macOS 系统设置：根据 settings.systemProxyEnabled / launchAtLogin 实际生效。
    /// 在 App Sandbox 下，systemProxy 的 networksetup 会失败 —— 给个 warn 日志而不是 crash。
    @MainActor
    public func applyMacSystemPreferences() {
        let loginActual = MacSystemServices.setLoginItem(settings.launchAtLogin, logger: logger)
        if loginActual != settings.launchAtLogin {
            settings.launchAtLogin = loginActual
        }
        if settings.systemProxyEnabled {
            _ = MacSystemServices.setSystemProxy(
                httpPort: settings.httpPort,
                socksPort: settings.socksPort,
                enabled: true,
                logger: logger
            )
        } else {
            _ = MacSystemServices.setSystemProxy(
                httpPort: settings.httpPort,
                socksPort: settings.socksPort,
                enabled: false,
                logger: logger
            )
        }
    }
}
#endif
