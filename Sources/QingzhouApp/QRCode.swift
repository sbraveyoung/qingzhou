import Foundation
import SwiftUI

#if canImport(CoreImage)
import CoreImage
import CoreImage.CIFilterBuiltins
#endif

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#endif

/// 生成二维码图片。失败时返回 nil（极少发生，仅当输入超过 QR 容量）。
public enum QRCode {
    public static func generate(from text: String, size: CGFloat = 240) -> PlatformImage? {
        #if canImport(CoreImage)
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        #if canImport(UIKit)
        return UIImage(cgImage: cg)
        #elseif canImport(AppKit)
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
        #endif
        #else
        return nil
        #endif
    }
}

/// SwiftUI 友好的二维码视图。
public struct QRCodeView: View {
    public let text: String
    public let size: CGFloat

    public init(text: String, size: CGFloat = 240) {
        self.text = text
        self.size = size
    }

    public var body: some View {
        if let image = QRCode.generate(from: text, size: size) {
            #if canImport(UIKit)
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)
            #elseif canImport(AppKit)
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)
            #endif
        } else {
            Text("二维码生成失败").foregroundStyle(.red)
        }
    }
}
