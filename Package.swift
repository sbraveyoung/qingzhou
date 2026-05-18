// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VPN",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "VPNCore",         targets: ["VPNCore"]),
        .library(name: "VPNProtocols",    targets: ["VPNProtocols"]),
        .library(name: "VPNSubscription", targets: ["VPNSubscription"]),
        .library(name: "VPNRules",        targets: ["VPNRules"]),
        .library(name: "VPNSpeedTest",    targets: ["VPNSpeedTest"]),
        .library(name: "VPNLogging",      targets: ["VPNLogging"]),
        .library(name: "VPNApp",          targets: ["VPNApp"]),
        .library(name: "XrayCore",        targets: ["XrayCore"])
    ],
    dependencies: [
        // Yams：Swift YAML 解析器，用于 Clash / Mihomo / Stash 配置导入。
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0")
    ],
    targets: [
        .target(name: "VPNCore"),
        .target(
            name: "VPNProtocols",
            dependencies: [
                "VPNCore",
                .product(name: "Yams", package: "Yams")
            ]
        ),
        .target(name: "VPNSubscription", dependencies: ["VPNCore", "VPNProtocols", "VPNLogging"]),
        .target(name: "VPNRules",        dependencies: ["VPNCore", "VPNLogging"]),
        .target(name: "VPNSpeedTest",    dependencies: ["VPNCore", "VPNLogging"]),
        .target(name: "VPNLogging",      dependencies: ["VPNCore"]),
        .target(
            name: "VPNApp",
            dependencies: [
                "VPNCore", "VPNProtocols", "VPNSubscription",
                "VPNRules", "VPNSpeedTest", "VPNLogging"
                // VPNApp 故意不依赖 XrayCore —— XrayCore 拖入 LibXray.xcframework（85 MB
                // Go runtime），dyld 在主 App 启动时强制加载完才进 main()，会黑屏 1–3 秒。
                // share link → 完整 xray 配置 的转换挪到了 Extension 里做，
                // 见 Apps/Tunnel-Shared/PacketTunnelProvider.swift。
            ]
        ),

        .testTarget(name: "VPNCoreTests",         dependencies: ["VPNCore"]),
        .testTarget(name: "VPNProtocolsTests",    dependencies: ["VPNProtocols"]),
        .testTarget(name: "VPNSubscriptionTests", dependencies: ["VPNSubscription"]),
        .testTarget(name: "VPNRulesTests",        dependencies: ["VPNRules"]),
        .testTarget(name: "VPNSpeedTestTests",    dependencies: ["VPNSpeedTest"]),
        .testTarget(name: "VPNLoggingTests",      dependencies: ["VPNLogging"]),
        .testTarget(name: "VPNAppTests",          dependencies: ["VPNApp"]),

        // ─────────────────────────────────────────────────────────────────────
        // XrayCore：Swift 包装 LibXray.xcframework（xray-core 的 MIT 移动端 binding）。
        // xcframework 由 scripts/build-libxray.sh 通过 libXray 上游脚本构建产出，
        // 文件不入库（体积大，~380MB）；首次构建后落在 Frameworks/LibXray.xcframework。
        // ─────────────────────────────────────────────────────────────────────
        .binaryTarget(
            name: "LibXray",
            path: "Frameworks/LibXray.xcframework"
        ),
        .target(
            name: "XrayCore",
            dependencies: ["LibXray", "VPNCore", "VPNLogging"],
            linkerSettings: [
                // libXray 内部用 res_9_* DNS resolver API（Darwin libresolv）
                .linkedLibrary("resolv")
            ]
        ),
        .testTarget(name: "XrayCoreTests", dependencies: ["XrayCore"])
    ]
)
