// System Extension 的入口。app-extension 靠 NSExtensionPrincipalClass 由系统实例化、不需要 main；
// system extension 是独立可执行程序，必须有 main 入口调用 startSystemExtensionMode()，
// 系统据 Info.plist 的 NEProviderClasses 实例化 FilterDataProvider。

import Foundation
import NetworkExtension

autoreleasepool {
    NEProvider.startSystemExtensionMode()
}

dispatchMain()
