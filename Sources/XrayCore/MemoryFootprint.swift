// MemoryFootprint —— 隧道扩展进程的内存采样（放 XrayCore：只有扩展 target 需要它）。
//
// 为什么采 phys_footprint 而不是 resident size：iOS 的 jetsam（内存杀手）对 NE 扩展
// 按 **phys_footprint ≥ 50 MiB** 判死刑（Apple DTS 确认），Xcode memory gauge 显示的
// 也是它。resident size 会把可被回收的干净页也算进去，虚高且与判死线无关。
//
// 采样本身必须轻：一次 task_info() mach call（微秒级、无分配），随现有每秒 stats
// 定时器顺带跑，失败静默返回 nil —— 观测代码绝不能反过来威胁被观测的进程。

import Darwin
import Foundation
#if canImport(os.proc)
import os.proc
#endif

public enum MemoryFootprint {

    /// 当前进程的 phys_footprint（字节）。jetsam 的判定依据。失败返回 nil。
    public static func currentFootprint() -> Int64? {
        var info = task_vm_info_data_t()
        // 只取到 phys_footprint 为止的字段数，内核允许截断返回（老系统字段更少也兼容）
        var count = mach_msg_type_number_t(
            MemoryLayout.offset(of: \task_vm_info_data_t.phys_footprint)! / MemoryLayout<integer_t>.size
        ) + 1
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return Int64(info.phys_footprint)
    }

    /// 距离 jetsam 上限还剩多少字节（os_proc_available_memory）。**仅 iOS 有意义**；
    /// macOS 上该 API 不可用（appex 无 jetsam 硬上限），返回 nil。
    public static func availableMemory() -> Int64? {
        #if os(iOS)
        let avail = os_proc_available_memory()
        // 文档：返回 0 表示"不适用/取不到"（比如带 entitlement 的特殊进程），当失败处理
        return avail > 0 ? Int64(avail) : nil
        #else
        return nil
        #endif
    }

    /// 平台的扩展内存硬上限（字节）。iOS NE 扩展 = 50 MiB；macOS 无硬上限 → 0。
    public static var platformLimitBytes: Int64 {
        #if os(iOS)
        return 50 * 1024 * 1024
        #else
        return 0
        #endif
    }
}
