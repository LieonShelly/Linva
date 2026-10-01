import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Metal

/// 图片纹理缓存（spec §4.1）：脏键 = 节点 id + 显示像素尺寸 + scale 桶 + 内容身份；
/// 命中 O(1) baseAddress/count 比对，miss（重建）时才算 FNV-1a 全哈希并 memoize；
/// 解码即降采样（CGImageSource thumbnail，按显示尺寸 × scale）；LRU 字节预算驱逐。
final class ImageTextureCache {
    /// 命中比对的源数据身份：持有 Data 值（COW，只加引用不拷贝字节）锁定缓冲区 + 预存 baseAddress/count。
    /// Node.image 每次 setImage 都是全新 Data、从不原地改 → 同缓冲区必同内容，身份相等 ⇔ 内容相等；
    /// 条目持有期间旧缓冲区不会被 allocator 复用作新内容，杜绝「地址复用误命中」——
    /// PNG 等长替换（prefix/suffix 恒为文件签名/IEND 尾）不再碰撞、新图必重建。
    private struct SourceData {
        let data: Data
        let address: UInt
        let count: Int
    }

    private struct Entry {
        let widthPx: Int
        let heightPx: Int
        let scaleMilli: Int          // Int((displayScale * 100).rounded())，与 TextAtlas 同法
        let fingerprint: Int         // FNV-1a 全哈希（miss 时算一次并 memoize）
        let source: SourceData
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
        localRect: CGRect,      // pt（= 图片块的局部 rect）
        payload: ImagePayload,
        displayScale: CGFloat,  // renderer 已乘 rasterBucket
        device: MTLDevice
    ) -> MTLTexture? {
        guard localRect.width > 0, localRect.height > 0 else { return nil }

        let widthPx = max(Int(ceil(localRect.width * displayScale)), 1)
        let heightPx = max(Int(ceil(localRect.height * displayScale)), 1)
        let scaleMilli = Int((displayScale * 100).rounded())

        // 命中：同维度 + 同 scale 桶 + 同内容身份（O(1)，不付 O(n) 全哈希）。
        let currentAddress = payload.data.withUnsafeBytes { $0.baseAddress.map { UInt(bitPattern: $0) } }
        if let cached = entries[id],
           cached.widthPx == widthPx,
           cached.heightPx == heightPx,
           cached.scaleMilli == scaleMilli,
           currentAddress == cached.source.address,
           payload.data.count == cached.source.count {
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

        // miss → 重建；此时才付 O(n) FNV-1a 全哈希并 memoize 进条目（命中路径已提前返回）。
        let sourceData = SourceData(
            data: payload.data,
            address: currentAddress ?? 0,
            count: payload.data.count
        )
        insert(
            id: id, widthPx: widthPx, heightPx: heightPx, scaleMilli: scaleMilli,
            fingerprint: Self.fnv1a(of: payload.data),
            source: sourceData, texture: texture, bytes: widthPx * heightPx * 4
        )
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

    /// 内容全哈希（spec §4.1 指纹语义修订：内容身份 / 全哈希）。
    /// FNV-1a 64 位，对任意字节差异敏感；只在校验 miss（重建）时计算一次并 memoize，
    /// 命中路径 O(1) baseAddress/count 身份比对、不付 O(n) 全哈希。
    /// 替代原「字节数 + 首尾 8 字节」：本应用图片全为 PNG，prefix/suffix 恒为文件签名
    /// 89504E470D0A1A0A / IEND 尾 49454E44AE426082，等长 PNG 指纹只剩字节数、全碰撞 → 显示旧图。
    /// 也不用 Data.hashValue：实测 NSData.hash 只取前缀字节，改尾部字节指纹不变。
    private static func fnv1a(of data: Data) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325   // FNV-1a 64 位 offset basis
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3              // FNV-1a 64 位 prime
        }
        return Int(truncatingIfNeeded: hash)
    }

    private func insert(
        id: UUID, widthPx: Int, heightPx: Int, scaleMilli: Int,
        fingerprint: Int, source: SourceData, texture: MTLTexture, bytes: Int
    ) {
        // 同节点脏键变化覆盖旧条目：先回吐旧字节，避免 bytesUsed 漂移导致误驱逐。
        if let old = entries[id] {
            bytesUsed -= old.bytes
        }
        tick += 1
        bytesUsed += bytes
        entries[id] = Entry(
            widthPx: widthPx, heightPx: heightPx, scaleMilli: scaleMilli,
            fingerprint: fingerprint, source: source, texture: texture, bytes: bytes, lastUse: tick
        )
        while bytesUsed > byteBudget, let victim = entries.min(by: { $0.value.lastUse < $1.value.lastUse }) {
            bytesUsed -= victim.value.bytes
            entries.removeValue(forKey: victim.key)
        }
    }
}
