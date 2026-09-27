import Testing
import Foundation
@testable import YMindApp

@Suite("MarkdownExporter")
struct MarkdownExporterTests {
    private func doc(rootText: String = "中心", children: [Node] = []) -> MindMapDocument {
        var d = MindMapDocument.blank(rootText: rootText)
        d.root.children = children
        return d
    }

    @Test func rootOnly_singleHash() {
        #expect(MarkdownExporter.markdown(from: doc(rootText: "根")) == "# 根\n")
    }

    @Test func nestedDepth_addsHash() {
        var d = doc(rootText: "根", children: [Node(text: "一层")])
        d.root.children[0].children = [Node(text: "二层")]
        #expect(MarkdownExporter.markdown(from: d) == "# 根\n\n## 一层\n\n### 二层\n")
    }

    @Test func depthBeyondSix_cappedAtH6() {
        var node = Node(text: "最深层")
        for _ in 0..<6 { node = Node(text: "层", children: [node]) }
        var d = doc(rootText: "根")
        d.root.children = [node]
        let lines = MarkdownExporter.markdown(from: d).split(separator: "\n")
        #expect(lines.last!.hasPrefix("###### "))
        #expect(!lines.last!.hasPrefix("####### "))
    }

    @Test func collapsedBranch_stillFullyExported() {
        let grand = Node(text: "孙")
        let child = Node(text: "子", collapsed: true, side: .right, children: [grand])
        #expect(MarkdownExporter.markdown(from: doc(children: [child])).contains("### 孙"))
    }

    @Test func multilineText_collapsedToSingleLine() {
        let md = MarkdownExporter.markdown(from: doc(rootText: "第一行\r\n第二行\n\n  第三行  "))
        #expect(md == "# 第一行 第二行 第三行\n")
    }

    @Test func emptyText_becomesUnnamed() {
        #expect(MarkdownExporter.markdown(from: doc(rootText: "   \n  ")) == "# 未命名\n")
    }

    @Test func fillAndSideMetadata_notEmitted() {
        let child = Node(text: "有填色", side: .left, fill: .sage)
        #expect(MarkdownExporter.markdown(from: doc(children: [child])) == "# 中心\n\n## 有填色\n")
    }
}

@Suite("ExportNaming")
struct ExportNamingTests {
    @Test func illegalCharacters_replaced() {
        #expect(ExportNaming.safeFilename(base: "a/b\\c:d", ext: "png") == "a_b_c_d.png")
    }
    @Test func whitespaceRuns_collapsedToSingleSpace() {
        #expect(ExportNaming.safeFilename(base: "  我的  图\n表 ", ext: "md") == "我的 图 表.md")
    }
    @Test func emptyBase_fallsBackToYmind() {
        #expect(ExportNaming.safeFilename(base: "   ", ext: "png") == "ymind.png")
    }
    @Test func longBase_truncated() {
        let long = String(repeating: "a", count: 100)
        #expect(ExportNaming.safeFilename(base: long, ext: "md").hasPrefix(String(repeating: "a", count: 48)))
    }
}
