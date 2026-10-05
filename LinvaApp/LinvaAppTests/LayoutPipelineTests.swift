import CoreGraphics
import Foundation
import Testing
@testable import LinvaApp

@Suite("LayoutPipeline")
struct LayoutPipelineTests {
    @Test func radialDocument_usesRadialLayout() {
        var doc = MindMapDocument.blank()
        doc.root.children = [Node(text: "子", side: .right)]
        let pipeline = LayoutPipeline()
        let snap = pipeline.relayout(document: doc)
        // 引擎只产排布；连线由默认 elbow Provider 产。
        let placed = RadialLayout.place(document: doc, measure: TextMeasure())
        #expect(snap.frames == placed.frames)
        #expect(snap.branchToggles == placed.branchToggles)
        #expect(snap.imagePayloads == placed.imagePayloads)
        #expect(snap.connectors.count == 1)
    }

    @Test func logicDocument_usesLogicLayout() {
        var doc = MindMapDocument.blank(rootText: "根")
        doc.layout = .logic
        let child = Node(text: "章", children: [Node(text: "节")])
        doc.root.children = [child]

        let pipeline = LayoutPipeline()
        let snap = pipeline.relayout(document: doc)
        let placed = LogicLayout.place(document: doc, measure: TextMeasure())
        #expect(snap.frames == placed.frames)
        #expect(snap.branchToggles == placed.branchToggles)
        #expect(snap.imagePayloads == placed.imagePayloads)
        #expect(snap.frames[child.id]!.center.x > snap.frames[doc.root.id]!.rect.maxX)
        // 默认 elbow 样式：2 对父子 2 条折线。
        #expect(snap.connectors.count == 2)
    }

    /// brace 强制逻辑树（D3）：radial 布局下按总分树排布 + 组括号 Connector。
    @Test func brace_forcesLogicArrangement_andGroupConnectors() throws {
        var doc = MindMapDocument.blank(rootText: "根")
        doc.layout = .radial
        doc.edgeStyle = .brace
        let chapter = Node(text: "章", children: [Node(text: "节")])
        doc.root.children = [chapter]

        let snap = LayoutPipeline().relayout(document: doc)
        // 有效排布 = 逻辑树：根最左（rootPadX）、子在其右。
        let root = try #require(snap.frames[doc.root.id])
        let cf = try #require(snap.frames[chapter.id])
        #expect(root.rect.minX == LayoutConstants.rootPadX)
        #expect(cf.center.x > root.rect.maxX)
        // 两个有子父 → 两个组括号 Connector（id=父节点）。
        #expect(snap.connectors.count == 2)
        #expect(snap.connectors.map(\.id) == [doc.root.id, chapter.id])
    }

    /// curve 样式不改排布：沿用 document.layout，产每边曲线 Connector。
    @Test func curve_keepsDocumentLayout_andProducesCurves() {
        var doc = MindMapDocument.blank()
        doc.edgeStyle = .curve
        let child = Node(text: "子", side: .right)
        doc.root.children = [child]

        let snap = LayoutPipeline().relayout(document: doc)
        #expect(snap.frames == RadialLayout.place(document: doc, measure: TextMeasure()).frames)
        #expect(snap.connectors.count == 1)
        #expect(snap.connectors[0].path.count == 21)  // 20 段采样
    }
}
