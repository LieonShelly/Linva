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

    @Test func branchNode_isHeading_leaf_isList() {
        // 根(分支)→子(叶子)：根标题，子列表项（深度2 → `- `）
        let d = doc(rootText: "根", children: [Node(text: "子")])
        #expect(MarkdownExporter.markdown(from: d) == "# 根\n\n- 子\n")
    }

    @Test func deepBranch_staysHeading_deepLeaf_isList() {
        // 深层分支节点仍是标题，只有叶子变列表
        var node = Node(text: "最深层")
        for _ in 0..<5 { node = Node(text: "层", children: [node]) }
        var d = doc(rootText: "根")
        d.root.children = [node]
        let lines = MarkdownExporter.markdown(from: d).split(separator: "\n")
        // 5 个 "层" 都是分支 → 标题（深度2-6）；最深层是叶子（深度7）→ 列表（符号 +）
        #expect(lines.contains("## 层"))
        #expect(lines.contains("### 层"))
        #expect(lines.contains("###### 层"))
        #expect(lines.contains("+ 最深层"))
        #expect(!lines.contains { $0.hasPrefix("#######") })
    }

    @Test func mixedDepthTree_branchHeading_leafList() {
        // 同层兄弟对齐：root → (二级分支→深叶子, 浅叶子a, 浅叶子b)
        // 深度2 存在分支（二级分支）→ 深度2 全为标题（浅叶子a/b 也是 ##）
        var leaf2 = Node(text: "深叶子")        // depth3 叶子 → `* `
        var branch2 = Node(text: "二级分支", children: [leaf2])  // depth2 分支 → ##
        var leaf1a = Node(text: "浅叶子a")       // depth2 叶子，但同层有分支 → 标题
        var leaf1b = Node(text: "浅叶子b")
        var d = doc(rootText: "根", children: [branch2, leaf1a, leaf1b])
        let md = MarkdownExporter.markdown(from: d)
        #expect(md.contains("\n## 二级分支\n"))
        #expect(md.contains("\n## 浅叶子a\n"))
        #expect(md.contains("\n## 浅叶子b\n"))
        #expect(md.contains("\n* 深叶子\n"))
        #expect(!md.contains("\n- 浅叶子a"))
    }

    @Test func siblingAlignment_leafBecomesHeading_ifSiblingBranches() {
        // 用户场景：root → (A有三级, B无子)。A 是分支 → 深度2 全标题，B 也变标题
        let a = Node(text: "A", children: [Node(text: "a三级")])
        let b = Node(text: "B")
        let d = doc(rootText: "root", children: [a, b])
        let md = MarkdownExporter.markdown(from: d)
        #expect(md.contains("\n## A\n"))
        #expect(md.contains("\n## B\n"))
        #expect(md.contains("\n* a三级\n"))
    }

    @Test func leafSymbol_cyclesByDepth() {
        // root(d1)→d3分支(d2)→d4分支(d3)→d5叶(d4)
        // 叶子深度2→`-`、3→`*`、4→`+`、5→`-`（循环）
        var d5 = Node(text: "d5")
        var d4 = Node(text: "d4", children: [d5])
        var d3 = Node(text: "d3", children: [d4])
        var d = doc(rootText: "根", children: [d3])
        let md = MarkdownExporter.markdown(from: d)
        #expect(md.contains("\n+ d5\n"))          // depth4 → `+`
        #expect(!md.contains("- d5"))
        // 单独验证 depth5 → `-`（回环）：
        var dd = doc(rootText: "根", children: [Node(text: "d2", children: [Node(text: "d3", children: [Node(text: "d4", children: [Node(text: "d5")])])])])
        #expect(MarkdownExporter.markdown(from: dd).contains("\n- d5\n"))
    }

    @Test func deepBranch_doesNotRaiseSiblingGroupHeadings() {
        // 用户不满足场景：深分支 B 不应拉高 A 分支下的浅叶子 a1
        // root → (A→a1无子, B→b1→b1x无子)
        var b1x = Node(text: "b1x")
        var b1 = Node(text: "b1", children: [b1x])
        var a1 = Node(text: "a1")
        var d = doc(rootText: "root", children: [Node(text: "A", children: [a1]), Node(text: "B", children: [b1])])
        let md = MarkdownExporter.markdown(from: d)
        // A、B 组（root 直接子）有分支 → 全 Title
        #expect(md.contains("\n## A\n"))
        #expect(md.contains("\n## B\n"))
        // a1 组无分支 → Content
        #expect(md.contains("\n* a1\n"))
        #expect(!md.contains("### a1"))
        // b1 有子 → Title；b1x 组无分支 → Content
        #expect(md.contains("\n### b1\n"))
        #expect(md.contains("\n+ b1x\n"))
    }

    @Test func rootAlwaysHeading_evenIfLeaf() {
        // 根节点即使无子节点也是标题
        #expect(MarkdownExporter.markdown(from: doc(rootText: "孤根")) == "# 孤根\n")
    }

    @Test func collapsedBranch_stillFullyExported() {
        let grand = Node(text: "孙")
        let child = Node(text: "子", collapsed: true, side: .right, children: [grand])
        // 子有子节点=分支标题；孙为叶子（深度3）→ `* 孙`
        #expect(MarkdownExporter.markdown(from: doc(children: [child])).contains("\n* 孙"))
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
        // 子为叶子 → 列表项（深度2 → `- `）
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
