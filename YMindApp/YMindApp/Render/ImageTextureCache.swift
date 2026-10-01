import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Metal

/// 图片纹理缓存（spec §4.1）：脏键 = 节点 id + 显示像素尺寸 + scale 桶 + 数据指纹；
/// 解码即降采样（CGImageSource thumbnail，按显示尺寸 × scale）；LRU 字节预算驱逐。
final class ImageTextureCache {
    private struct CacheKey: Equatable {
        let widthPx: Int
        let heightPx: Int
        let scaleMilli: Int          // Int((displayScale * 100).rounded())，与 TextAtlas 同法
        let dataFingerprint: Int     // 字节数 + 首尾 8 字节（spec §4.1）
    }

    private struct Entry {
        let key: CacheKey
        let texture: MTLTexture
        let bytes: Int
        var lastUse: Int
    }

    private let byteBudget: Int
    private var entries: [UUID: Entry] = [:]
    private var tick = 0
    private var bytesUsed = 0

    init(byteBudget: Int = 128 * 1024 * 1024) {
        self.byteBudget = byteBudget
    }

    /// 返回已按显示尺寸降采样的纹理；脏键命中直接复用，否则解码重建。
    /// 数据非法 / 解码失败 → nil（按无图显示，降级不崩）。
    func texture(
        id: UUID,
        localRect: CGRect,      // pt（= frame.imageRect）
        payload: ImagePayload,
        displayScale: CGFloat,  // renderer 已乘 rasterBucket
        device: MTLDevice
    ) -> MTLTexture? {
        guard localRect.width > 0, localRect.height > 0 else { return nil }

        let widthPx = max(Int(ceil(localRect.width * displayScale)), 1)
        let heightPx = max(Int(ceil(localRect.height * displayScale)), 1)
        let key = CacheKey(
            widthPx: widthPx,
            heightPx: heightPx,
            scaleMilli: Int((displayScale * 100).rounded()),
            dataFingerprint: Self.fingerprint(of: payload.data)
        )

        if let cached = entries[id], cached.key == key {
            touch(id)
            return cached.texture
        }

        // 解码即降采样：按显示像素尺寸出图，而非原图尺寸（显存较原图路径降 4~6×）。
        guard let source = CGImageSourceCreateWithData(payload.data as CFData, nil) else { return nil }
        let maxPixel = max(widthPx, heightPx)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil   // 数据非法 → 按无图显示（spec 容错）
        }

        // 画进 RGBA 位图（同文字纹理格式），保留 flipVertically 行翻转（ymind-render-text 纪律）。
        // makeBitmap 的 draw 闭包在 flipped NSGraphicsContext 下执行；这里用翻转把 CGImage
        // 摆正，再经内部 flipVertically 得到「首行=顶边」的纹理。若目测图片上下颠倒，只允许
        // 调整这里的 y 翻转，禁止删 flipVertically。
        guard let bitmap = TextTextureRasterizer.makeBitmap(
            width: widthPx,
            height: heightPx,
            displayScale: 1,
            draw: {
                NSGraphicsContext.current?.cgContext.interpolationQuality = .high
                let cgContext = NSGraphicsContext.current!.cgContext
                cgContext.saveGState()
                cgContext.translateBy(x: 0, y: CGFloat(heightPx))
                cgContext.scaleBy(x: 1, y: -1)
                cgContext.draw(cg, in: CGRect(x: 0, y: 0, width: widthPx, height: heightPx))
                cgContext.restoreGState()
            }
        ) else { return nil }

        guard let texture = TextTextureRasterizer.makeTexture(
            device: device, width: widthPx, height: heightPx,
            bitmap: bitmap, label: "图片纹理 \(id)"
        ) else { return nil }

        insert(id: id, key: key, texture: texture, bytes: widthPx * heightPx * 4)
        return texture
    }

    /// 帧不在 `known` 集合内的条目全部释放（回屏后按需重建）。
    func evictUnused(known: Set<UUID>) {
        let stale = entries.keys.filter { !known.contains($0) }
        for id in stale {
            if let entry = entries.removeValue(forKey: id) {
                bytesUsed -= entry.bytes
            }
        }
    }

    private func touch(_ id: UUID) {
        tick += 1
        entries[id]?.lastUse = tick
    }

    /// 数据指纹（spec §4.1：字节数 + 首尾 8 字节）。
    /// 不用 Data.hashValue：实测 NSData.hash 只取前缀字节，改尾部字节指纹不变
    /// → 脏键失效、显示旧图；首尾字节公式 O(1)、确定性、跨进程稳定。
    private static func fingerprint(of data: Data) -> Int {
        var h = data.count &* 31
        for byte in data.prefix(8) { h = h &* 31 &+ Int(byte) }
        for byte in data.suffix(8) { h = h &* 31 &+ Int(byte) }
        return h
    }

    private func insert(id: UUID, key: CacheKey, texture: MTLTexture, bytes: Int) {
        // 同节点脏键变化覆盖旧条目：先回吐旧字节，避免 bytesUsed 漂移导致误驱逐。
        if let old = entries[id] {
            bytesUsed -= old.bytes
        }
        tick += 1
        bytesUsed += bytes
        entries[id] = Entry(key: key, texture: texture, bytes: bytes, lastUse: tick)
        while bytesUsed > byteBudget, let victim = entries.min(by: { $0.value.lastUse < $1.value.lastUse }) {
            bytesUsed -= victim.value.bytes
            entries.removeValue(forKey: victim.key)
        }
    }
}
