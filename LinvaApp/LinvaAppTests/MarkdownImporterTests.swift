import Testing
import Foundation
@testable import LinvaApp

@Suite("MarkdownImporter")
struct MarkdownImporterTests {
    private func parse(_ md: String) throws -> MindMapDocument {
        try MarkdownImporter().parse(Data(md.utf8))
    }
    private func text(_ node: Node) -> String { node.text }

    @Test func firstHeading_isRoot() throws {
        let doc = try parse("# 中心主题\n## 子上")
        #expect(doc.root.text == "中心主题")
        #expect(doc.root.children.count == 1)
        #expect(text(doc.root.children[0]) == "子上")
    }

    @Test func headingDepth_mapsDepth_andLevelGapConnectsDirectly() throws {
        // # A → 根；### C 深度3（缺 ## 层）→ 直连到最近祖先(根)；## B 深度2 → 挂根下
        let doc = try parse("# A\n### C\n## B")
        #expect(doc.root.text == "A")
        // 出现顺序：C 先(深度3直连根)、B 后(深度2直连根) —— 二者都是根的直接子
        #expect(doc.root.children.map(\.text) == ["C", "B"])
    }

    @Test func listItems_hangUnderMostRecentHeading() throws {
        let doc = try parse("# root\n- item1\n- item2\n## sub\n- subitem")
        #expect(doc.root.children.map(\.text) == ["item1", "item2", "sub"])
        let sub = doc.root.children.first { $0.text == "sub" }!
        #expect(sub.children.map(\.text) == ["subitem"])
    }

    @Test func allListSymbols_imported() throws {
        // 导出器用 - / * / + 区分层级，导入需全部识别
        let doc = try parse("# root\n- dash\n* star\n+ plus\n• bullet")
        #expect(doc.root.children.map(\.text) == ["dash", "star", "plus", "bullet"])
    }

    @Test func emptyText_becomesUnnamed() throws {
        let doc = try parse("# root\n##   \n-  ")
        #expect(doc.root.children[0].text == "未命名")
        #expect(doc.root.children[0].children[0].text == "未命名")
    }

    @Test func fragmentsBeforeFirstHeading_ignored() throws {
        let doc = try parse("随便的段落\n不是标题\n# root\n- ok")
        #expect(doc.root.text == "root")
        #expect(doc.root.children.count == 1)
    }

    @Test func noHeadingAtAll_throwsUnrecognized() {
        #expect(throws: ImportError.unrecognizedOutline) {
            _ = try parse("- 只有列表\n- 没有标题")
        }
    }

    @Test func rootChildren_getAlternatingSide() throws {
        let doc = try parse("# root\n- a\n- b\n- c")
        #expect(doc.root.children.map(\.side) == [.left, .right, .left])
    }

    @Test func inlineMarkdown_keptAsLiteral() throws {
        let doc = try parse("# root\n- **bold** [link](url)")
        #expect(doc.root.children[0].text == "**bold** [link](url)")
    }

    @Test func headingBeyondSix_cappedAtSix() throws {
        let doc = try parse("# root\n####### 深度七")
        #expect(doc.root.children.contains { $0.text == "深度七" })
    }
}