// YMindAppTests/PNGExporterTests.swift
import Testing
import AppKit
import ImageIO
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

    @Test func data_bigTree_notClampedToFixedPixels() throws {
        // 回归：旧实现用固定长边 2400 硬降采样，上千节点大树被压成窄图而模糊。
        // 现在改为「面积预算驱动」——包围盒长边 ~29000pt 的树应导出高分辨率大图，
        // 而非被 clamp 到 ~2400px 长边。断言输出图像素总数远超旧上限。
        try #require(MTLCreateSystemDefaultDevice() != nil)
        func grow(_ p: String, _ d: Int) -> Node {
            var n = Node(text: "\(p)-\(d)")
            if d > 0 { n.children = (0..<3).map { grow("\(p).\($0)", d - 1) } }
            return n
        }
        var d = MindMapDocument.blank(rootText: "根")
        d.root.children = (0..<6).map { i in
            var c = grow("B\(i)", 5)
            if i % 2 == 0 { c.side = .left }
            return c
        }
        let data = try #require(PNGExporter.data(document: d))
        // 解码尺寸
        let src = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let pw = (props?[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let ph = (props?[kCGImagePropertyPixelHeight] as? Int) ?? 0
        // 旧上限长边 2400；预算驱动后应远大于此（包围盒长边 ~29000 × scale≈1.5）
        #expect(pw > 1500 && ph > 8000, "大树 PNG 被压回固定小图：\(pw)x\(ph)")
    }
}
