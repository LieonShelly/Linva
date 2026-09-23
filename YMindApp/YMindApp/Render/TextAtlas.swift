import AppKit
import CoreText
import Metal

final class TextAtlas {
    private struct CacheKey: Equatable {
        let text: String
        let width: Int
        let height: Int
        let scale: Int
        let isRoot: Bool
    }

    private struct CacheEntry {
        let key: CacheKey
        let texture: MTLTexture
    }

    private var entries: [UUID: CacheEntry] = [:]

    func texture(
        for frame: NodeFrame,
        text: String,
        scale: CGFloat,
        device: MTLDevice
    ) -> MTLTexture? {
        let displayScale = max(scale, 1)
        let width = max(Int(ceil(frame.size.width * displayScale)), 1)
        let height = max(Int(ceil(frame.size.height * displayScale)), 1)
        let key = CacheKey(
            text: text,
            width: width,
            height: height,
            scale: Int((displayScale * 100).rounded()),
            isRoot: frame.isRoot
        )

        if let cached = entries[frame.id], cached.key == key {
            return cached.texture
        }

        guard let bitmap = makeBitmap(
            frame: frame,
            text: text,
            displayScale: displayScale,
            width: width,
            height: height
        ) else {
            return nil
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }

        texture.label = "文字纹理 \(frame.id)"
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: bitmap,
            bytesPerRow: width * 4
        )
        entries[frame.id] = CacheEntry(key: key, texture: texture)
        return texture
    }

    private func makeBitmap(
        frame: NodeFrame,
        text: String,
        displayScale: CGFloat,
        width: Int,
        height: Int
    ) -> [UInt8]? {
        var bitmap = [UInt8](repeating: 0, count: width * height * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }

        let created = bitmap.withUnsafeMutableBytes { bytes -> Bool in
            guard let baseAddress = bytes.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                        | CGImageAlphaInfo.premultipliedFirst.rawValue
                  ) else {
                return false
            }

            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: displayScale, y: displayScale)

            let font = NSFont.systemFont(
                ofSize: frame.isRoot ? 18.4 : 14.7,
                weight: frame.isRoot ? .bold : .medium
            )
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byCharWrapping
            let attributedText = NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: NSColor.white,
                    .paragraphStyle: paragraph,
                ]
            )

            let horizontalPadding: CGFloat = frame.isRoot
                ? LayoutConstants.rootPadX
                : LayoutConstants.nodePadX
            let verticalPadding: CGFloat = frame.isRoot
                ? LayoutConstants.rootPadY
                : LayoutConstants.nodePadY
            let textRect = CGRect(
                x: horizontalPadding,
                y: verticalPadding,
                width: max(frame.size.width - horizontalPadding * 2, 1),
                height: max(frame.size.height - verticalPadding * 2, 1)
            )
            let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
            let path = CGPath(rect: textRect, transform: nil)
            let textFrame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: 0, length: attributedText.length),
                path,
                nil
            )
            CTFrameDraw(textFrame, context)
            return true
        }

        return created ? bitmap : nil
    }
}
