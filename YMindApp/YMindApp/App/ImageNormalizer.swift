import AppKit
import ImageIO
import Foundation

/// 图片归一器（FR-G1 入口）：任意图片数据 → 受控 PNG bytes + 像素尺寸。
/// 流程：CGImageSource 解码（gif 取首帧）→ 最长边 >1024 等比缩 → PNG 编码
/// → 仍 >5MB 再降 512 → 仍超限 nil（调用方提示，不入栈）。
enum ImageNormalizer {
    private static let maxPixelEdge: Int = 1024
    private static let secondPassEdge: Int = 512
    // 8-bit 源 1024² 编码 ≈3.4MB 恒不超限；仅深色深度源（16-bit 等）会触发二级降采样
    private static let maxEncodedBytes = 5 * 1024 * 1024

    static func normalize(_ data: Data) -> (data: Data, pixelSize: ImagePixelSize)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let original = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        var cg = original
        let maxEdge = max(cg.width, cg.height)
        if maxEdge > maxPixelEdge {
            let scale = CGFloat(maxPixelEdge) / CGFloat(maxEdge)
            guard let scaled = drawScaled(cg, scale: scale) else { return nil }
            cg = scaled
        }

        var encoded = encodePNG(cg)
        if (encoded?.count ?? 0) > maxEncodedBytes {
            // 二级降采样：8-bit 源 1024² 编码 ≈3.4MB 恒不触发；仅深色深度源（如 16-bit 噪声）可能超 5MB
            let scale = CGFloat(secondPassEdge) / CGFloat(max(CGFloat(cg.width), CGFloat(cg.height)))
            if let smaller = drawScaled(cg, scale: scale) {
                cg = smaller  // 成功时必须同步更新 cg：pixelSize 须与返回 bytes 一致
                encoded = encodePNG(smaller)
            }
        }
        guard let bytes = encoded, bytes.count <= maxEncodedBytes,
              let size = ImagePixelSize(width: Double(cg.width), height: Double(cg.height)) else {
            return nil
        }
        // PNG 编码含透明通道与颜色配置，尺寸以最终 CGImage（含二级降采样结果）为准
        return (bytes, size)
    }

    private static func drawScaled(_ image: CGImage, scale: CGFloat) -> CGImage? {
        let width = max(Int((CGFloat(image.width) * scale).rounded()), 1)
        let height = max(Int((CGFloat(image.height) * scale).rounded()), 1)
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func encodePNG(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
