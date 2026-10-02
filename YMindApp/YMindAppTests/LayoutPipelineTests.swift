import CoreGraphics
import Foundation
import Testing
@testable import YMindApp

@Suite("LayoutPipeline")
struct LayoutPipelineTests {
    @Test func radialDocument_usesRadialLayout() {
        let pipeline = LayoutPipeline()
        let doc = MindMapDocument.blank()
        let snap = pipeline.relayout(document: doc)
        let expected = RadialLayout.layout(document: doc, measure: TextMeasure())
        #expect(snap == expected)
    }

    @Test func logicDocument_usesLogicLayout() {
        var doc = MindMapDocument.blank(rootText: "根")
        doc.layout = .logic
        let child = Node(text: "章", children: [Node(text: "节")])
        doc.root.children = [child]

        let pipeline = LayoutPipeline()
        let snap = pipeline.relayout(document: doc)
        let expected = LogicLayout.layout(document: doc, measure: TextMeasure())
        #expect(snap == expected)
        #expect(snap.frames[child.id]!.center.x > snap.frames[doc.root.id]!.rect.maxX)
    }
}
