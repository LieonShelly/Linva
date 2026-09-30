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

    @Test func nestedDepth_withinTitleDepth_addsHash() {
        // maxDepth=3 → titleDepth=2：深度1、2 为标题，深度3 为列表项
        var d = doc(rootText: "根", children: [Node(text: "一层")])
        d.root.children[0].children = [Node(text: "二层")]
        #expect(MarkdownExporter.markdown(from: d) == "# 根\n\n## 一层\n\n- 二层\n")
    }

    @Test func depthBeyondTitleDepth_becomesListItems() {
        // maxDepth=7 → titleDepth=3：深度4+ 全为列表项，缩进递增，永不出现 #### 标题
        var node = Node(text: "最深层")
        for _ in 0..<6 { node = Node(text: "层", children: [node]) }
        var d = doc(rootText: "根")
        d.root.children = [node]
        let lines = MarkdownExporter.markdown(from: d).split(separator: "\n")
        #expect(!lines.contains { $0.hasPrefix("####") })
        // 深度4（titleDepth+1）→ 无缩进列表；最深层深度8 → 8 空格缩进列表
        #expect(lines.contains { $0 == "- 层" })
        #expect(lines.contains { $0.hasPrefix("        - 最深层") })
    }

    @Test func titleDepth_adaptsToShallowTree() {
        // maxDepth=2 → titleDepth=1：深度1 标题、深度2 列表项
        let d = doc(rootText: "根", children: [Node(text: "子")])
        #expect(MarkdownExporter.markdown(from: d) == "# 根\n\n- 子\n")
    }

    @Test func titleDepth_capsAtThree_forDeepTree() {
        // maxDepth=5 → titleDepth=3：深度1-3 标题、深度4-5 列表项
        var node = Node(text: "d4")
        node.children = [Node(text: "d5")]
        var d = doc(rootText: "根")
        d.root.children = [Node(text: "d2", children: [Node(text: "d3", children: [node])])]
        let md = MarkdownExporter.markdown(from: d)
        #expect(md.contains("### d3"))
        #expect(md.contains("- d4"))
        #expect(md.contains("  - d5"))
    }

    @Test func contentList_nestedIndentation() {
        // 深度4 → 无缩进；深度5 → 2 空格；深度6 → 4 空格
        var d6 = Node(text: "d6")
        var d5 = Node(text: "d5", children: [d6])
        var d4 = Node(text: "d4", children: [d5])
        var d = doc(rootText: "根")
        d.root.children = [Node(text: "d2", children: [Node(text: "d3", children: [d4])])]
        let md = MarkdownExporter.markdown(from: d)
        #expect(md.contains("\n- d4\n"))
        #expect(md.contains("\n  - d5\n"))
        #expect(md.contains("\n    - d6\n"))
    }

    @Test func collapsedBranch_stillFullyExported() {
        let grand = Node(text: "孙")
        let child = Node(text: "子", collapsed: true, side: .right, children: [grand])
        // maxDepth=3 → titleDepth=2：孙（深度3）为列表项
        #expect(MarkdownExporter.markdown(from: doc(children: [child])).contains("\n- 孙"))
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
        // maxDepth=2 → titleDepth=1：子节点（深度2）为列表项
        #expect(MarkdownExporter.markdown(from: doc(children: [child])) == "# 中心\n\n- 有填色\n")
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
