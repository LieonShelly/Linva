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
