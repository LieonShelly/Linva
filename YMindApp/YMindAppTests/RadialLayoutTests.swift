import Testing
import Foundation
import CoreGraphics
@testable import YMindApp

@Suite("RadialLayout")
struct RadialLayoutTests {
    @Test func singleRoot_centeredAtOrigin() {
        let doc = MindMapDocument.blank()
        let snap = RadialLayout.layout(document: doc, measure: TextMeasure())
        let root = snap.frames[doc.root.id]!
        #expect(root.center == .zero)
        #expect(snap.edges.isEmpty)
    }

    @Test func leftAndRight_childrenOppositeX() {
        var doc = MindMapDocument.blank()
        let left = Node(text: "L", side: .left)
        let right = Node(text: "R", side: .right)
        doc.root.children = [left, right]
        let snap = RadialLayout.layout(document: doc, measure: TextMeasure())
        let lf = snap.frames[left.id]!
        let rf = snap.frames[right.id]!
        #expect(lf.center.x < 0)
        #expect(rf.center.x > 0)
        #expect(snap.edges.count == 2)
    }

    @Test func collapsed_hidesDescendants() {
        var doc = MindMapDocument.blank()
        let grand = Node(text: "孙")
        let child = Node(text: "子", collapsed: true, side: .right, children: [grand])
        doc.root.children = [child]
        let snap = RadialLayout.layout(document: doc, measure: TextMeasure())
        #expect(snap.frames[grand.id] == nil)
        #expect(snap.frames[child.id]?.hiddenCount == 1)
        let badge = snap.frames[child.id].flatMap(CollapseBadge.make(for:))
        #expect(badge?.text == "1")
        #expect(badge?.nodeId == child.id)
    }

    @Test func collapseBadge_onlyAppearsForCollapsedNodesWithHiddenDescendants() {
        let leaf = NodeFrame(
            id: UUID(),
            text: "叶",
            center: .zero,
            size: NodeSize(width: 80, height: 40),
            isRoot: false,
            side: .right,
            collapsed: true,
            hiddenCount: 0
        )
        let expanded = NodeFrame(
            id: UUID(),
            text: "展开",
            center: .zero,
            size: NodeSize(width: 80, height: 40),
            isRoot: false,
            side: .right,
            collapsed: false,
            hiddenCount: 3
        )

        #expect(CollapseBadge.make(for: leaf) == nil)
        #expect(CollapseBadge.make(for: expanded) == nil)
    }

    @Test func siblingsOnSameSide_areVerticallyCenteredWithGap() throws {
        var doc = MindMapDocument.blank()
        let first = Node(text: "A", side: .right)
        let second = Node(text: "B", side: .right)
        doc.root.children = [first, second]

        let snap = RadialLayout.layout(document: doc, measure: TextMeasure())
        let firstFrame = try #require(snap.frames[first.id])
        let secondFrame = try #require(snap.frames[second.id])

        #expect(firstFrame.center.y == -secondFrame.center.y)
        #expect(
            secondFrame.center.y - firstFrame.center.y
                == firstFrame.size.height + LayoutConstants.vGap
        )
    }

    @Test func descendants_inheritBranchSideAndMoveOutward() throws {
        var doc = MindMapDocument.blank()
        let grandchild = Node(text: "孙")
        let child = Node(text: "子", side: .left, children: [grandchild])
        doc.root.children = [child]

        let snap = RadialLayout.layout(document: doc, measure: TextMeasure())
        let childFrame = try #require(snap.frames[child.id])
        let grandchildFrame = try #require(snap.frames[grandchild.id])
        let edge = try #require(snap.edges.last)

        #expect(grandchildFrame.side == .left)
        #expect(grandchildFrame.center.x < childFrame.center.x)
        #expect(edge.points.count == 4)
        #expect(edge.points.first?.x == childFrame.rect.minX)
        #expect(edge.points.last?.x == grandchildFrame.rect.maxX)
    }

    @Test func textMeasure_preservesExplicitEmptyLines() {
        let measure = TextMeasure()
        let oneLine = measure.size(for: Node(text: ""), isRoot: false)
        let twoLines = measure.size(for: Node(text: "\n"), isRoot: false)

        #expect(oneLine.height == LayoutConstants.nodeLineHeight + LayoutConstants.nodePadY * 2)
        #expect(twoLines.height == LayoutConstants.nodeLineHeight * 2 + LayoutConstants.nodePadY * 2)
    }
}
