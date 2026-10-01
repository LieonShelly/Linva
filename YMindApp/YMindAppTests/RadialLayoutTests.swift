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
        let toggle = snap.branchToggles.first { $0.nodeId == child.id }
        #expect(toggle?.collapsed == true)
        #expect(toggle?.hiddenCount == 1)
        #expect(toggle?.side == .right)
    }

    @Test func branchToggle_onExpandedParent_showsPlusSemanticsFields() {
        var doc = MindMapDocument.blank()
        let child = Node(text: "子", side: .right, children: [Node(text: "孙")])
        doc.root.children = [child]
        let snap = RadialLayout.layout(document: doc, measure: TextMeasure())
        let toggles = snap.branchToggles.filter { $0.nodeId == child.id }
        #expect(toggles.count == 1)
        #expect(toggles[0].collapsed == false)
        #expect(toggles[0].side == .right)
        #expect(toggles[0].center.x > snap.frames[child.id]!.rect.maxX)
    }

    @Test func root_collapsed_stillHasLeftAndRightToggles() {
        var doc = MindMapDocument.blank()
        doc.root.children = [
            Node(text: "L", side: .left),
            Node(text: "R", side: .right),
        ]
        doc.root.collapsed = true
        let snap = RadialLayout.layout(document: doc, measure: TextMeasure())
        let sides = Set(snap.branchToggles.filter { $0.nodeId == doc.root.id }.map(\.side))
        #expect(sides == [.left, .right])
        #expect(snap.frames.count == 1)
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

    @Test func frameCarriesNodeFill() {
        var doc = MindMapDocument.blank()
        doc.root.fill = .sage
        let child = Node(text: "子", side: .right, fill: .sky)
        doc.root.children = [child]
        let snap = RadialLayout.layout(document: doc, measure: TextMeasure())
        #expect(snap.frames[doc.root.id]?.fill == .sage)
        #expect(snap.frames[child.id]?.fill == .sky)
    }
}

@Suite("图片布局")
struct ImageLayoutTests {
    private func measure() -> TextMeasure { TextMeasure() }

    @Test func sizedNode_growsForImage_withinDisplayLimit() {
        var doc = MindMapDocument.blank(rootText: "根")
        // 图片 600×300pt 请求 → 上限 300 → 显示 300×150
        doc.root = Node(text: "根", image: Data([0x01]), imagePixelSize: ImagePixelSize(width: 600, height: 300))
        let snapshot = RadialLayout.layout(document: doc, measure: measure())
        let frame = snapshot.frames[doc.root.id]!

        let bare = MindMapDocument.blank(rootText: "根")
        let bareFrame = RadialLayout.layout(document: bare, measure: measure()).frames[bare.root.id]!

        #expect(frame.size.height == bareFrame.size.height + LayoutConstants.imageTextGap + 150)
        let imageBlocks = frame.blocks.filter { $0.text == nil }
        #expect(imageBlocks.count == 1)
        let rect = imageBlocks[0].rect
        #expect(rect.width == 300)
        #expect(abs(rect.height - 150) < 0.001)
        // 水平居中于节点
        #expect(abs(rect.midX - frame.size.width / 2) < 0.001)
        // payload 按块 id 索引
        #expect(snapshot.imagePayloads[imageBlocks[0].blockId] != nil)
    }

    @Test func smallImage_centered_whenTextDrivesWidth() {
        var doc = MindMapDocument.blank(rootText: "相当长的文字内容决定节点宽度")
        doc.root = Node(text: "相当长的文字内容决定节点宽度", image: Data([0x01]), imagePixelSize: ImagePixelSize(width: 50, height: 50))
        let snapshot = RadialLayout.layout(document: doc, measure: measure())
        let frame = snapshot.frames[doc.root.id]!
        let imageBlocks = frame.blocks.filter { $0.text == nil }
        #expect(imageBlocks.count == 1)
        let rect = imageBlocks[0].rect
        #expect(rect.width == 50)
        #expect(abs(rect.midX - frame.size.width / 2) < 0.001)
    }

    @Test func imagelessNode_hasNoImageBlocksOrPayload() {
        let doc = MindMapDocument.blank(rootText: "根")
        let snapshot = RadialLayout.layout(document: doc, measure: measure())
        #expect(snapshot.frames[doc.root.id]!.blocks.allSatisfy { $0.text != nil })
        #expect(snapshot.imagePayloads.isEmpty)
    }

    @Test func collapsedDescendantWithImage_isAbsentFromFramesAndPayloads() {
        var doc = MindMapDocument.blank(rootText: "根")
        let child = Node(text: "折叠", image: Data([0x01]), imagePixelSize: ImagePixelSize(width: 10, height: 10))
        doc.root.children = [child]
        doc.root.collapsed = true
        let snapshot = RadialLayout.layout(document: doc, measure: measure())
        #expect(snapshot.frames[child.id] == nil)
        #expect(snapshot.imagePayloads[child.id] == nil)
    }

    @Test func multipleBlocks_stackVerticallyInOrder() {
        var doc = MindMapDocument.blank(rootText: "根")
        let root = doc.root.id
        var node = doc.root
        node.blocks = [
            ContentBlock(id: UUID(), kind: .text("文")),
            ContentBlock(id: UUID(), kind: .image(.init(data: Data([0x01]), pixelSize: ImagePixelSize(width: 100, height: 100)!))),
            ContentBlock(id: UUID(), kind: .text("尾")),
        ]
        node.id = root
        doc.root = node
        let snapshot = RadialLayout.layout(document: doc, measure: measure())
        let frame = snapshot.frames[root]!
        let blocks = frame.blocks
        #expect(blocks.count == 3)
        #expect(blocks[0].text == "文")
        #expect(blocks[1].text == nil)
        #expect(blocks[2].text == "尾")
        #expect(blocks[1].rect.minY >= blocks[0].rect.maxY)
        #expect(blocks[2].rect.minY >= blocks[1].rect.maxY)
    }
}
