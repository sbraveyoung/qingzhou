#if os(macOS)
import AppKit
import Foundation

/// macOS 专用：监听用户指定的「触发 App」启动 / 退出，自动开 / 关 VPN。
///
/// 为什么 macOS 单独做：iOS 用「快捷指令 → 自动化 → App 已打开/已关闭」就能触发 App Intents，
/// 但 macOS 的 Shortcuts **没有** App 打开/关闭这个触发器。好在 macOS 主 App 是常驻菜单栏 agent，
/// 直接用 `NSWorkspace` 的启动/退出通知实现，原生可靠、不依赖 Shortcuts。
///
/// 语义：任一触发 App 启动 → onActivate（开 VPN）；最后一个触发 App 退出 → onDeactivate（关 VPN）。
@MainActor
public final class AppLaunchWatcher {
    private var launchObserver: NSObjectProtocol?
    private var quitObserver: NSObjectProtocol?
    private var triggers: Set<String> = []          // 触发 App 的 bundle id
    private let onActivate: () -> Void
    private let onDeactivate: () -> Void

    public init(onActivate: @escaping () -> Void, onDeactivate: @escaping () -> Void) {
        self.onActivate = onActivate
        self.onDeactivate = onDeactivate
    }

    /// 用一组触发 App 的 bundle id 开始监听。空集合等于停用。重复调用会先停旧的。
    public func start(triggers: Set<String>) {
        stop()
        self.triggers = triggers
        guard !triggers.isEmpty else { return }
        let nc = NSWorkspace.shared.notificationCenter
        launchObserver = nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let bid = Self.bundleID(from: note)   // 在 nonisolated 闭包里提取出 Sendable 的 String
            MainActor.assumeIsolated {            // queue: .main 保证在主线程，安全
                guard let self, let bid, self.triggers.contains(bid) else { return }
                self.onActivate()
            }
        }
        quitObserver = nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let bid = Self.bundleID(from: note)
            MainActor.assumeIsolated {
                guard let self, let bid, self.triggers.contains(bid) else { return }
                // 只有当没有任何触发 App 还在跑时才关，避免关掉一个 App 误断别的
                if !self.anyTriggerRunning() { self.onDeactivate() }
            }
        }
    }

    public func stop() {
        let nc = NSWorkspace.shared.notificationCenter
        if let o = launchObserver { nc.removeObserver(o); launchObserver = nil }
        if let o = quitObserver { nc.removeObserver(o); quitObserver = nil }
        triggers = []
    }

    /// 当前是否有任一触发 App 在运行。
    public func anyTriggerRunning() -> Bool {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return !triggers.isDisjoint(with: running)
    }

    nonisolated private static func bundleID(from note: Notification) -> String? {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
    }
}
#endif
