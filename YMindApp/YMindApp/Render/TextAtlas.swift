import AppKit
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

        guard let bitmap = TextTextureRasterizer.makeBitmap(
            width: width,
            height: height,
            displayScale: displayScale,
            draw: { attributedText.draw(in: textRect) }
        ) else {
            return nil
        }

        guard let texture = TextTextureRasterizer.makeTexture(
            device: device,
            width: width,
            height: height,
            bitmap: bitmap,
            label: "文字纹理 \(frame.id)"
        ) else {
            return nil
        }

        entries[frame.id] = CacheEntry(key: key, texture: texture)
        return texture
    }
}

final class BranchToggleAtlas {
    private struct CacheKey: Equatable {
        let text: String
        let width: Int
        let height: Int
        let scale: Int
        let collapsed: Bool
    }

    private struct CacheEntry {
        let key: CacheKey
        let texture: MTLTexture
    }

    private var entries: [String: CacheEntry] = [:]

    static func label(for toggle: BranchToggle) -> String {
        // 图标表示「点击后的动作」：折叠态点击会展开整棵子树 → 加号；展开态点击会折叠 → 减号。
        if toggle.collapsed {
            return toggle.hiddenCount > 0 ? "＋\(toggle.hiddenCount)" : "＋"
        }
        return "−"
    }

    func texture(
        for toggle: BranchToggle,
        size: CGSize,
        scale: CGFloat,
        device: MTLDevice
    ) -> MTLTexture? {
        let displayScale = max(scale, 1)
        let width = max(Int(ceil(size.width * displayScale)), 1)
        let height = max(Int(ceil(size.height * displayScale)), 1)
        let text = Self.label(for: toggle)
        let cacheId = "\(toggle.nodeId.uuidString)-\(toggle.side.rawValue)"
        let key = CacheKey(
            text: text,
            width: width,
            height: height,
            scale: Int((displayScale * 100).rounded()),
            collapsed: toggle.collapsed
        )
        if let cached = entries[cacheId], cached.key == key {
            return cached.texture
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph,
            ]
        )
        let textRect = CGRect(origin: .zero, size: size)

        guard let bitmap = TextTextureRasterizer.makeBitmap(
            width: width,
            height: height,
            displayScale: displayScale,
            draw: {
                let bounding = attributedText.boundingRect(
                    with: textRect.size,
                    options: [.usesLineFragmentOrigin]
                )
                let drawRect = CGRect(
                    x: (textRect.width - bounding.width) / 2,
                    y: (textRect.height - bounding.height) / 2,
                    width: bounding.width,
                    height: bounding.height
                )
                attributedText.draw(with: drawRect, options: [.usesLineFragmentOrigin])
            }
        ) else {
            return nil
        }

        guard let texture = TextTextureRasterizer.makeTexture(
            device: device,
            width: width,
            height: height,
            bitmap: bitmap,
            label: "分叉控件纹理 \(cacheId)"
        ) else {
            return nil
        }

        entries[cacheId] = CacheEntry(key: key, texture: texture)
        return texture
    }
}

/// 用翻转的 AppKit 图形上下文栅格化文字，再把像素行翻成「首行=顶边」以上传 Metal。
enum TextTextureRasterizer {
    static func makeBitmap(
        width: Int,
        height: Int,
        displayScale: CGFloat,
        draw: () -> Void
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

            let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsContext
            defer { NSGraphicsContext.restoreGraphicsState() }

            let transform = NSAffineTransform()
            transform.scaleX(by: displayScale, yBy: displayScale)
            transform.concat()

            draw()
            return true
        }

        guard created else { return nil }
        flipVertically(&bitmap, width: width, height: height)
        return bitmap
    }

    /// CG/AppKit 位图缓冲往往底行在前；翻成顶行在前，与 Metal 纹理第 0 行一致。
    private static func flipVertically(_ bitmap: inout [UInt8], width: Int, height: Int) {
        let rowBytes = width * 4
        guard height > 1, rowBytes > 0 else { return }
        var temp = [UInt8](repeating: 0, count: rowBytes)
        for y in 0..<(height / 2) {
            let top = y * rowBytes
            let bottom = (height - 1 - y) * rowBytes
            temp.replaceSubrange(0..<rowBytes, with: bitmap[top..<(top + rowBytes)])
            bitmap.replaceSubrange(top..<(top + rowBytes), with: bitmap[bottom..<(bottom + rowBytes)])
            bitmap.replaceSubrange(bottom..<(bottom + rowBytes), with: temp[0..<rowBytes])
        }
    }

    static func makeTexture(
        device: MTLDevice,
        width: Int,
        height: Int,
        bitmap: [UInt8],
        label: String
    ) -> MTLTexture? {
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
        texture.label = label
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: bitmap,
            bytesPerRow: width * 4
        )
        return texture
    }
}
