#!/usr/bin/env swift
// 轻舟 App 图标生成器 · 方向 A「静海蓝」(ICON_BRIEF.md)
//
// 纯 CoreGraphics 矢量作画 → 按需缩放到任意像素，每个尺寸都清晰。
// 输出无 alpha 的 sRGB PNG（App Store 要求：无透明、无圆角；圆角交给 Apple）。
//
// 重新生成整套（在仓库根目录执行）：
//   IOS=Apps/iOS/Resources/Assets.xcassets/AppIcon.appiconset
//   MAC=Apps/macOS/Resources/Assets.xcassets/AppIcon.appiconset
//   swift scripts/gen_app_icon.swift \
//     1024 "$IOS/icon_1024.png" \
//     16 "$MAC/icon_16.png"  32 "$MAC/icon_16@2x.png" \
//     32 "$MAC/icon_32.png"  64 "$MAC/icon_32@2x.png" \
//     128 "$MAC/icon_128.png" 256 "$MAC/icon_128@2x.png" \
//     256 "$MAC/icon_256.png" 512 "$MAC/icon_256@2x.png" \
//     512 "$MAC/icon_512.png" 1024 "$MAC/icon_512@2x.png"
//
// 调设计只改下面的画法；颜色对应 brief 方向 A：#3A6FBE / #2C5694 / #E8F2FF。

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: a)
}
let sky   = rgb(58, 111, 190)   // #3A6FBE 深海蓝
let water = rgb(44, 86, 148)    // #2C5694 暗一档的水
let snow  = rgb(232, 242, 255)  // #E8F2FF 雪雾白

func render(_ S: Int, to path: String) {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        fatalError("ctx \(S)")
    }
    // 左上原点 + 缩放到目标尺寸，之后全部用 1024 坐标系作画
    ctx.translateBy(x: 0, y: CGFloat(S))
    ctx.scaleBy(x: 1, y: -1)
    let k = CGFloat(S) / 1024.0
    ctx.scaleBy(x: k, y: k)
    ctx.interpolationQuality = .high

    ctx.setFillColor(sky)
    ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    ctx.setFillColor(water)
    ctx.fill(CGRect(x: 0, y: 672, width: 1024, height: 352))

    // 月牙：白圆挖去一块天空色圆
    ctx.setFillColor(snow)
    ctx.fillEllipse(in: CGRect(x: 748-86, y: 268-86, width: 172, height: 172))
    ctx.setFillColor(sky)
    ctx.fillEllipse(in: CGRect(x: 712-86, y: 242-86, width: 172, height: 172))

    // 船体
    let hull = CGMutablePath()
    hull.move(to: CGPoint(x: 366, y: 694))
    hull.addLine(to: CGPoint(x: 658, y: 694))
    hull.addLine(to: CGPoint(x: 628, y: 726))
    hull.addQuadCurve(to: CGPoint(x: 396, y: 726), control: CGPoint(x: 512, y: 752))
    hull.closeSubpath()
    ctx.setFillColor(snow); ctx.addPath(hull); ctx.fillPath()

    // 桅杆
    ctx.setFillColor(snow)
    ctx.fill(CGRect(x: 506, y: 486, width: 12, height: 208))

    // 一面弧形帆
    let sail = CGMutablePath()
    sail.move(to: CGPoint(x: 522, y: 492))
    sail.addQuadCurve(to: CGPoint(x: 628, y: 688), control: CGPoint(x: 648, y: 598))
    sail.addLine(to: CGPoint(x: 522, y: 688))
    sail.closeSubpath()
    ctx.setFillColor(snow); ctx.addPath(sail); ctx.fillPath()

    // 水面倒影
    ctx.setFillColor(rgb(232, 242, 255, 0.22))
    ctx.fill(CGRect(x: 424, y: 748, width: 176, height: 7))
    ctx.setFillColor(rgb(232, 242, 255, 0.15))
    ctx.fill(CGRect(x: 450, y: 770, width: 128, height: 6))

    guard let img = ctx.makeImage() else { fatalError("img \(S)") }
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("dest \(path)")
    }
    CGImageDestinationAddImage(dest, img, nil)
    if !CGImageDestinationFinalize(dest) { fatalError("write \(path)") }
    print("✓ \(S)px → \(path)")
}

let args = Array(CommandLine.arguments.dropFirst())
var i = 0
while i + 1 < args.count {
    render(Int(args[i])!, to: args[i+1])
    i += 2
}
