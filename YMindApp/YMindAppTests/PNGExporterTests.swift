// YMindAppTests/PNGExporterTests.swift
import Testing
import AppKit
@testable import YMindApp

@Suite("PNGExporter")
struct PNGExporterTests {
    @Test func fullyExpanded_clearsAllCollapsed_andKeepsOriginal() {
        let grand = Node(text: "孙", collapsed: true)
        let child = Node(text: "子", collapsed: true, children: [grand])
        var d = MindMapDocument.blank(rootText: "根")
        d.root.children = [child]

        let expanded = PNGExporter.fullyExpanded(d)
        #expect(expanded.root.children[0].collapsed == false)
        #expect(expanded.root.children[0].children[0].collapsed == false)
        // 原文档折叠态不变
        #expect(d.root.children[0].collapsed == true)
    }

    @Test func data_rendersPNG_whenMetalAvailable() throws {
        // 无 Metal 设备的环境跳过（macOS 测试宿主通常有）。
        try #require(MTLCreateSystemDefaultDevice() != nil)
        var d = MindMapDocument.blank(rootText: "根")
        let grand = Node(text: "孙")
        let child = Node(text: "子", collapsed: true, fill: .sage, children: [grand])
        d.root.children = [child]

        let data = PNGExporter.data(document: d)
        #expect(data != nil)
        // PNG 魔数
        let sig = data?.prefix(8)
        #expect(sig == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        // 折叠态仍保持（FR-E3 验收 1：导后折叠仍在）
        #expect(d.root.children[0].collapsed == true)
    }
}

@Suite("PNG 导出含图")
struct PNGWithImageTests {
    @Test func exportedPNG_containsImagePixels() throws {
        // 造 4×4 纯红 PNG
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep!)
        NSColor.red.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 4, height: 4)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let png = rep!.representation(using: .png, properties: [:])!

        var doc = MindMapDocument.blank(rootText: "根")
        doc.root = Node(text: "根", image: png, imagePixelSize: ImagePixelSize(width: 100, height: 100))

        let data = try #require(PNGExporter.data(document: doc))
        let outRep = try #require(NSBitmapImageRep(data: data))

        // 找根节点在导出快照中的图片区中心像素 → 应为红色（导出视口含全图）
        let expanded = PNGExporter.fullyExpanded(doc)
        let snapshot = RadialLayout.layout(document: expanded, measure: TextMeasure())
        let frame = try #require(snapshot.frames[doc.root.id])
        let imageBlock = try #require(frame.blocks.first { $0.text == nil })
        let local = imageBlock.rect
        let worldRect = CGRect(
            x: frame.rect.minX + local.minX, y: frame.rect.minY + local.minY,
            width: local.width, height: local.height)
        let bounds = snapshot.frames.values.reduce(CGRect.null) { $0.union($1.rect) }
        // renderImage: bounds + padding 48，长边缩到 2400；按同公式换算像素坐标
        let scale = min(max(2400 / max(bounds.width, bounds.height), 0.35), 2)
        let originX = bounds.minX - 48
        let originY = bounds.minY - 48
        let px = Int((worldRect.midX - originX) * scale)
        let py = Int((worldRect.midY - originY) * scale)
        guard let color = outRep.colorAt(x: px, y: py) else {
            Issue.record("像素越界")
            return
        }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(r > 0.6 && g < 0.4 && b < 0.4)
    }
}
