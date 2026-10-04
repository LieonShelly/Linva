import CoreGraphics
import Foundation
import Testing
@testable import YMindApp

@Suite("LogicLayout 总分树")
struct LogicLayoutTests {
    @Test func rootAtFarLeft_childrenToTheRight() throws {
        var doc = MindMapDocument.blank(rootText: "根")
        doc.layout = .logic
        let a = Node(text: "章一")
        let b = Node(text: "章二")
        doc.root.children = [a, b]

        let placed = LogicLayout.place(document: doc, measure: TextMeasure())
        let root = try #require(placed.frames[doc.root.id])
        let af = try #require(placed.frames[a.id])
        let bf = try #require(placed.frames[b.id])

        #expect(root.isRoot)
        #expect(root.side == nil)
        #expect(af.side == .right)
        #expect(af.center.x > root.rect.maxX)
        #expect(bf.center.x > root.rect.maxX)
        #expect(root.rect.minX == LayoutConstants.rootPadX)
    }

    @Test func siblings_stackVerticallyWithGap() throws {
        var doc = MindMapDocument.blank(rootText: "根")
        doc.layout = .logic
        let a = Node(text: "A")
        let b = Node(text: "B")
        doc.root.children = [a, b]

        let placed = LogicLayout.place(document: doc, measure: TextMeasure())
        let af = try #require(placed.frames[a.id])
        let bf = try #require(placed.frames[b.id])
        #expect(bf.rect.minY - af.rect.maxY == LayoutConstants.vGap)
    }

    @Test func descendants_moveFurtherRight() throws {
        var doc = MindMapDocument.blank(rootText: "根")
        doc.layout = .logic
        let grand = Node(text: "节")
        let chapter = Node(text: "章", children: [grand])
        doc.root.children = [chapter]

        let placed = LogicLayout.place(document: doc, measure: TextMeasure())
        let cf = try #require(placed.frames[chapter.id])
        let gf = try #require(placed.frames[grand.id])
        #expect(gf.center.x > cf.rect.maxX)
    }

    @Test func collapsedBranch_hidesDescendants_toggleOnRight() throws {
        var doc = MindMapDocument.blank(rootText: "根")
        doc.layout = .logic
        let grand = Node(text: "孙")
        let child = Node(text: "子", collapsed: true, children: [grand])
        doc.root.children = [child]

        let placed = LogicLayout.place(document: doc, measure: TextMeasure())
        #expect(placed.frames[grand.id] == nil)
        let cf = try #require(placed.frames[child.id])
        #expect(cf.hiddenCount == 1)
        let toggle = try #require(placed.branchToggles.first { $0.nodeId == child.id })
        #expect(toggle.side == .right)
        #expect(toggle.collapsed == true)
        #expect(toggle.center.x > cf.rect.maxX)
    }

    @Test func rootCollapsed_degenerateSnapshot_singleRightToggle() throws {
        var doc = MindMapDocument.blank(rootText: "根")
        doc.layout = .logic
        doc.root.children = [Node(text: "章")]
        doc.root.collapsedLeft = true
        doc.root.collapsedRight = true

        let placed = LogicLayout.place(document: doc, measure: TextMeasure())
        #expect(placed.frames.count == 1)
        let toggles = placed.branchToggles.filter { $0.nodeId == doc.root.id }
        #expect(toggles.count == 1)
        #expect(toggles[0].side == .right)
    }

    @Test func imageNode_collectsPayload() throws {
        var doc = MindMapDocument.blank(rootText: "根")
        doc.layout = .logic
        doc.root.children = [
            Node(text: "带图", image: Data([0x89, 0x50]), imagePixelSize: ImagePixelSize(width: 100, height: 50)),
        ]
        let placed = LogicLayout.place(document: doc, measure: TextMeasure())
        let frame = try #require(placed.frames[doc.root.children[0].id])
        let imageBlock = try #require(frame.blocks.first { $0.text == nil })
        #expect(placed.imagePayloads[imageBlock.blockId] != nil)
    }

    @Test func longTextNodes_doNotOverlap() throws {
        var doc = MindMapDocument.blank(rootText: "根")
        doc.layout = .logic
        let long = Node(text: String(repeating: "很长的章节标题内容", count: 8))
        let short = Node(text: "短")
        doc.root.children = [long, short]

        let placed = LogicLayout.place(document: doc, measure: TextMeasure())
        let lf = try #require(placed.frames[long.id])
        let sf = try #require(placed.frames[short.id])
        #expect(lf.size.width > sf.size.width)
        #expect(sf.rect.minY - lf.rect.maxY == LayoutConstants.vGap)
    }
}
