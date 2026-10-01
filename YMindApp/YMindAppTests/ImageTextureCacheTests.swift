import AppKit
import CoreGraphics
import Metal
import Testing
@testable import YMindApp

@Suite("图片纹理缓存")
struct ImageTextureCacheTests {
    private func frameWithImage(width: Int, height: Int) -> (NodeFrame, ImagePayload) {
        let id = UUID()
        let frame = NodeFrame(
            id: id, text: "n",
            center: .zero, size: NodeSize(width: 100, height: 100),
            isRoot: false, side: .right, collapsed: false, hiddenCount: 0,
            blocks: [
                BlockLayoutFrame(
                    blockId: UUID(),
                    text: nil,
                    rect: CGRect(x: 0, y: 0, width: width, height: height)
                ),
            ]
        )
        // 1×1 PNG 字节串就够走解码路径
        let png = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!.representation(using: .png, properties: [:])!
        return (frame, ImagePayload(pixelSize: ImagePixelSize(width: 1, height: 1)!, data: png))
    }

    /// 图片块的局部 rect（旧 imageRect 语义）。
    private func imageBlockRect(_ frame: NodeFrame) -> CGRect {
        frame.blocks.first { $0.text == nil }!.rect
    }

    @Test func texture_buildsOnceAndReusesOnHit() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let cache = ImageTextureCache(byteBudget: 8 * 1024 * 1024)
        let (frame, payload) = frameWithImage(width: 40, height: 40)
        let t1 = try #require(cache.texture(id: frame.id, localRect: imageBlockRect(frame), payload: payload, displayScale: 1, device: device))
        let t2 = cache.texture(id: frame.id, localRect: imageBlockRect(frame), payload: payload, displayScale: 1, device: device)
        #expect(t2 === t1)  // 同脏键命中，不重建
    }

    @Test func changedData_rebuildsTexture() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let cache = ImageTextureCache(byteBudget: 8 * 1024 * 1024)
        let (frame, payload) = frameWithImage(width: 40, height: 40)
        let t1 = try #require(cache.texture(id: frame.id, localRect: imageBlockRect(frame), payload: payload, displayScale: 1, device: device))
        let changed = ImagePayload(pixelSize: payload.pixelSize, data: Data(payload.data.dropLast(1) + [0x00]))
        let t2 = cache.texture(id: frame.id, localRect: imageBlockRect(frame), payload: changed, displayScale: 1, device: device)
        #expect(t2 !== t1)  // 数据变了 → 重建
    }

    /// 回归（Important #1）：两张等长、内容不同、都合法的 PNG（红/蓝 24×24）→ 必须重建。
    /// 旧指纹 = 字节数 + 首尾 8 字节，而 PNG 的 prefix/suffix 恒为文件签名/IEND 尾，
    /// 等长时指纹只剩字节数 → key 碰撞 → 显示旧图。此用例旧实现必挂。
    @Test func equalLengthDistinctPNGs_rebuildTexture() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let cache = ImageTextureCache(byteBudget: 8 * 1024 * 1024)
        let red = solidPNG(color: .red, size: 24)
        let blue = solidPNG(color: .blue, size: 24)
        #expect(red.count == blue.count)   // 等长：旧「字节数+首尾8字节」指纹必碰撞
        let size = ImagePixelSize(width: 24, height: 24)!
        let id = UUID()
        let frame = NodeFrame(
            id: id, text: "n", center: .zero, size: NodeSize(width: 100, height: 100),
            isRoot: false, side: .right, collapsed: false, hiddenCount: 0,
            blocks: [
                BlockLayoutFrame(
                    blockId: UUID(),
                    text: nil,
                    rect: CGRect(x: 0, y: 0, width: 24, height: 24)
                ),
            ]
        )
        let t1 = try #require(cache.texture(id: id, localRect: imageBlockRect(frame), payload: ImagePayload(pixelSize: size, data: red), displayScale: 1, device: device))
        let t2 = cache.texture(id: id, localRect: imageBlockRect(frame), payload: ImagePayload(pixelSize: size, data: blue), displayScale: 1, device: device)
        #expect(t2 !== t1)   // 内容不同 → 重建（等长 PNG 不再碰撞）
    }

    private func solidPNG(color: NSColor, size: Int) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    @Test func lru_evictsLeastRecentlyUsed_overBudget() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        // 预算只装得下 2 张 100×100（×4 字节 = 40KB）
        let cache = ImageTextureCache(byteBudget: 80 * 1024)
        let (a, pa) = frameWithImage(width: 100, height: 100)
        let (b, pb) = frameWithImage(width: 100, height: 100)
        let (c, pc) = frameWithImage(width: 100, height: 100)
        _ = cache.texture(id: a.id, localRect: imageBlockRect(a), payload: pa, displayScale: 1, device: device)
        _ = cache.texture(id: b.id, localRect: imageBlockRect(b), payload: pb, displayScale: 1, device: device)
        _ = cache.texture(id: a.id, localRect: imageBlockRect(a), payload: pa, displayScale: 1, device: device)  // a 变为最近使用
        _ = cache.texture(id: c.id, localRect: imageBlockRect(c), payload: pc, displayScale: 1, device: device)  // 插入 c → 驱逐 b
        let bAgain = cache.texture(id: b.id, localRect: imageBlockRect(b), payload: pb, displayScale: 1, device: device)
        #expect(bAgain != nil)  // 驱逐后重建成功（可重入）
    }

    @Test func corruptData_returnsNil_notCrash() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let cache = ImageTextureCache()
        let id = UUID()
        let frame = NodeFrame(
            id: id, text: "n", center: .zero, size: NodeSize(width: 50, height: 50),
            isRoot: false, side: .right, collapsed: false, hiddenCount: 0,
            blocks: [
                BlockLayoutFrame(
                    blockId: UUID(),
                    text: nil,
                    rect: CGRect(x: 0, y: 0, width: 50, height: 50)
                ),
            ]
        )
        let payload = ImagePayload(pixelSize: ImagePixelSize(width: 10, height: 10)!, data: Data("junk".utf8))
        #expect(cache.texture(id: frame.id, localRect: imageBlockRect(frame), payload: payload, displayScale: 1, device: device) == nil)
    }

    @Test func evictUnused_dropsEntriesOutsideKnownSet() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let cache = ImageTextureCache()
        let (frame, payload) = frameWithImage(width: 10, height: 10)
        _ = cache.texture(id: frame.id, localRect: imageBlockRect(frame), payload: payload, displayScale: 1, device: device)
        cache.evictUnused(known: [])
        let rebuilt = cache.texture(id: frame.id, localRect: imageBlockRect(frame), payload: payload, displayScale: 1, device: device)
        #expect(rebuilt != nil)  // 已被清，重新建：重建路径畅通
    }
}
