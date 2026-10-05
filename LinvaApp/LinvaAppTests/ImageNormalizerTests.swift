import AppKit
import ImageIO
import AVFoundation
import UniformTypeIdentifiers
import Testing
@testable import LinvaApp

@Suite("图片归一")
struct ImageNormalizerTests {
    /// 生成纯色位图 → 指定格式 bytes
    private func imageData(width: Int, height: Int, color: NSColor = .red) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:]) // 先产 PNG 源
    }

    @Test func pngRoundTrip_keepsPixelsWithinLimit() throws {
        let source = try #require(imageData(width: 800, height: 400))
        let result = try #require(ImageNormalizer.normalize(source))
        #expect(result.pixelSize == ImagePixelSize(width: Double(800), height: Double(400)))
        #expect(NSImage(data: result.data) != nil)  // 输出可再解码
    }

    @Test func oversizeImage_downscalesTo1024() throws {
        let source = try #require(imageData(width: 2048, height: 1024))
        let result = try #require(ImageNormalizer.normalize(source))
        #expect(result.pixelSize == ImagePixelSize(width: Double(1024), height: Double(512)))
    }

    @Test func nonImageData_returnsNil() {
        #expect(ImageNormalizer.normalize(Data("not an image".utf8)) == nil)
        #expect(ImageNormalizer.normalize(Data()) == nil)
    }

    @Test func gifInput_takesFirstFrame() throws {
        // 单帧 GIF 源
        let png = try #require(imageData(width: 64, height: 64))
        let cg = try #require(NSImage(data: png)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let gifBuffer = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(
            gifBuffer, UTType.gif.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cg, nil)
        #expect(CGImageDestinationFinalize(dest))
        let gifData = gifBuffer as Data
        #expect(!gifData.isEmpty)
        let result = try #require(ImageNormalizer.normalize(gifData))
        #expect(result.pixelSize == ImagePixelSize(width: Double(64), height: Double(64)))
    }

    @Test func heicInput_convertsToPNG() throws {
        let png = try #require(imageData(width: 100, height: 50))
        let cg = try #require(NSImage(data: png)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, AVFileType.heic.rawValue as CFString, 1, nil) else {
            return  // HEIC 编码器不可用的环境直接跳过（断言不失败）
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else {
            return  // HEIC 编码器不可用的环境直接跳过（断言不失败）
        }
        let result = try #require(ImageNormalizer.normalize(data as Data))
        #expect(result.pixelSize == ImagePixelSize(width: Double(100), height: Double(50)))
    }

    @Test func sixteenBitNoise_overLimitTriggersSecondPass() throws {
        // 16-bit 噪声 1024²：PNG 编码 >5MB，触发二级降采样。
        // 回归：pixelSize 必须与返回 bytes 实际尺寸一致、最长边 ≤512（防 512² bytes / 1024² pixelSize 矛盾）。
        let width = 1024, height = 1024
        let count = width * height * 4
        var samples = [UInt16](repeating: 0, count: count)
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        for i in 0..<count {
            seed = (seed &* 6364136223846793005) &+ 1442695040888963407
            samples[i] = UInt16(truncatingIfNeeded: seed >> 32)
        }
        let pixelData = samples.withUnsafeBytes { Data($0) }
        let provider = try #require(CGDataProvider(data: pixelData as CFData))
        let cg = try #require(CGImage(
            width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 64,
            bytesPerRow: width * 8, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let png = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(
            png, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cg, nil)
        #expect(CGImageDestinationFinalize(dest))
        #expect(png.length > 5 * 1024 * 1024)  // 源须 >5MB 才会进二级分支（可达性前置）
        let result = try #require(ImageNormalizer.normalize(png as Data))
        #expect(result.pixelSize.width <= 512)
        #expect(result.pixelSize.height <= 512)
        // pixelSize 必须等于返回 PNG 的实际像素尺寸
        let outRep = try #require(NSBitmapImageRep(data: result.data))
        #expect(result.pixelSize == ImagePixelSize(width: Double(outRep.pixelsWide), height: Double(outRep.pixelsHigh)))
    }
}
