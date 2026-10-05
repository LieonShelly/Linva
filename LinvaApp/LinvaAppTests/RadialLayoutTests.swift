import Testing
import Foundation
import CoreGraphics
@testable import LinvaApp

@Suite("RadialLayout")
struct RadialLayoutTests {
    @Test func singleRoot_centeredAtOrigin() {
        let doc = MindMapDocument.blank()
        let placed = RadialLayout.place(document: doc, measure: TextMeasure())
        let root = placed.frames[doc.root.id]!
        #expect(root.center == .zero)
        // 单根无子 → 无 toggle、无载荷。
        #expect(placed.branchToggles.isEmpty)
        #expect(placed.imagePayloads.isEmpty)
    }

    @Test func leftAndRight_childrenOppositeX() {
        var doc = MindMapDocument.blank()
        let left = Node(text: "L", side: .left)
        let right = Node(text: "R", side: .right)
        doc.root.children = [left, right]
        let placed = RadialLayout.place(document: doc, measure: TextMeasure())
        let lf = placed.frames[left.id]!
        let rf = placed.frames[right.id]!
        #expect(lf.center.x < 0)
        #expect(rf.center.x > 0)
        #expect(placed.frames.count == 3)
    }

    @Test func collapsed_hidesDescendants() {
        var doc = MindMapDocument.blank()
        let grand = Node(text: "孙")
        let child = Node(text: "子", collapsed: true, side: .right, children: [grand])
        doc.root.children = [child]
        let placed = RadialLayout.place(document: doc, measure: TextMeasure())
        #expect(placed.frames[grand.id] == nil)
        #expect(placed.frames[child.id]?.hiddenCount == 1)
        let toggle = placed.branchToggles.first { $0.nodeId == child.id }
        #expect(toggle?.collapsed == true)
        #expect(toggle?.hiddenCount == 1)
        #expect(toggle?.side == .right)
    }

    @Test func branchToggle_onExpandedParent_showsPlusSemanticsFields() {
        var doc = MindMapDocument.blank()
        let child = Node(text: "子", side: .right, children: [Node(text: "孙")])
        doc.root.children = [child]
        let placed = RadialLayout.place(document: doc, measure: TextMeasure())
        let toggles = placed.branchToggles.filter { $0.nodeId == child.id }
        #expect(toggles.count == 1)
        #expect(toggles[0].collapsed == false)
        #expect(toggles[0].side == .right)
        #expect(toggles[0].center.x > placed.frames[child.id]!.rect.maxX)
    }

    @Test func root_collapsed_stillHasLeftAndRightToggles() {
        var doc = MindMapDocument.blank()
        doc.root.children = [
            Node(text: "L", side: .left),
            Node(text: "R", side: .right),
        ]
        doc.root.collapsedLeft = true
        doc.root.collapsedRight = true
        let placed = RadialLayout.place(document: doc, measure: TextMeasure())
        let sides = Set(placed.branchToggles.filter { $0.nodeId == doc.root.id }.map(\.side))
        #expect(sides == [.left, .right])
        #expect(placed.frames.count == 1)
    }

    @Test func rootLeftCollapsed_hidesOnlyLeftSide() {
        var doc = MindMapDocument.blank()
        let l = Node(text: "L", side: .left, children: [Node(text: "L1")])
        let r = Node(text: "R", side: .right, children: [Node(text: "R1")])
        doc.root.children = [l, r]
        doc.root.collapsedLeft = true
        let placed = RadialLayout.place(document: doc, measure: TextMeasure())
        // 只隐藏左侧：左子树无 frame，右子树保留。
        #expect(placed.frames[l.id] == nil)
        #expect(placed.frames[l.children[0].id] == nil)
        #expect(placed.frames[r.id] != nil)
        #expect(placed.frames[r.children[0].id] != nil)
        // 根左右 toggle 折叠态各自独立。
        let leftToggle = placed.branchToggles.first { $0.nodeId == doc.root.id && $0.side == .left }
        #expect(leftToggle?.collapsed == true)
        #expect(leftToggle?.hiddenCount == 2)
        let rightToggle = placed.branchToggles.first { $0.nodeId == doc.root.id && $0.side == .right }
        #expect(rightToggle?.collapsed == false)
    }

    @Test func siblingsOnSameSide_areVerticallyCenteredWithGap() throws {
        var doc = MindMapDocument.blank()
        let first = Node(text: "A", side: .right)
        let second = Node(text: "B", side: .right)
        doc.root.children = [first, second]

        let placed = RadialLayout.place(document: doc, measure: TextMeasure())
        let firstFrame = try #require(placed.frames[first.id])
        let secondFrame = try #require(placed.frames[second.id])

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

        let placed = RadialLayout.place(document: doc, measure: TextMeasure())
        let childFrame = try #require(placed.frames[child.id])
        let grandchildFrame = try #require(placed.frames[grandchild.id])

        #expect(grandchildFrame.side == .left)
        #expect(grandchildFrame.center.x < childFrame.center.x)
    }

    @Test func textMeasure_preservesExplicitEmptyLines() {
        let measure = TextMeasure()
        let oneLine = measure.size(for: Node(text: ""), isRoot: false)
        let twoLines = measure.size(for: Node(text: "\n"), isRoot: false)

        #expect(oneLine.height == LayoutConstants.nodeLineHeight + LayoutConstants.nodePadY * 2)
        #expect(twoLines.height == LayoutConstants.nodeLineHeight * 2 + LayoutConstants.nodePadY * 2)
    }

    @Test func textBlock_minY_keepsVerticalPadding() {
        // 旧观感：TextAtlas 整盒内 textRect.y = verticalPadding → 纯文本节点文字顶 = 盒顶 + vPad（上下对称）。
        let measure = TextMeasure()
        let node = measure.measure(for: Node(text: "文"), isRoot: false)
        #expect(node.blocks.count == 1)
        #expect(node.blocks[0].rect.minY == LayoutConstants.nodePadY)
        #expect(node.size.height - node.blocks[0].rect.maxY == LayoutConstants.nodePadY)

        let root = measure.measure(for: Node(text: "根"), isRoot: true)
        #expect(root.blocks[0].rect.minY == LayoutConstants.rootPadY)
        #expect(root.size.height - root.blocks[0].rect.maxY == LayoutConstants.rootPadY)
    }

    @Test func frameCarriesNodeFill() {
        var doc = MindMapDocument.blank()
        doc.root.fill = .sage
        let child = Node(text: "子", side: .right, fill: .sky)
        doc.root.children = [child]
        let placed = RadialLayout.place(document: doc, measure: TextMeasure())
        #expect(placed.frames[doc.root.id]?.fill == .sage)
        #expect(placed.frames[child.id]?.fill == .sky)
    }
}

@Suite("图片布局")
struct ImageLayoutTests {
    private func measure() -> TextMeasure { TextMeasure() }

    @Test func sizedNode_growsForImage_withinDisplayLimit() {
        var doc = MindMapDocument.blank(rootText: "根")
        // 图片 600×300pt 请求 → 上限 300 → 显示 300×150
        doc.root = Node(text: "根", image: Data([0x01]), imagePixelSize: ImagePixelSize(width: 600, height: 300))
        let placed = RadialLayout.place(document: doc, measure: measure())
        let frame = placed.frames[doc.root.id]!

        let bare = MindMapDocument.blank(rootText: "根")
        let bareFrame = RadialLayout.place(document: bare, measure: measure()).frames[bare.root.id]!

        #expect(frame.size.height == bareFrame.size.height + LayoutConstants.imageTextGap + 150)
        let imageBlocks = frame.blocks.filter { $0.text == nil }
        #expect(imageBlocks.count == 1)
        let rect = imageBlocks[0].rect
        #expect(rect.width == 300)
        #expect(abs(rect.height - 150) < 0.001)
        // 水平居中于节点
        #expect(abs(rect.midX - frame.size.width / 2) < 0.001)
        // payload 按块 id 索引
        #expect(placed.imagePayloads[imageBlocks[0].blockId] != nil)
    }

    @Test func childWithImage_nonCollapsedRoot_payloadIncluded() {
        // 回归：非折叠布局需在 placeSide 后二次收集，非根子节点图片块也须有载荷。
        var doc = MindMapDocument.blank(rootText: "根")
        let child = Node(
            text: "子",
            side: .right,
            image: Data([0x01]),
            imagePixelSize: ImagePixelSize(width: 100, height: 50)
        )
        doc.root.children = [child]
        let placed = RadialLayout.place(document: doc, measure: measure())
        let childFrame = placed.frames[child.id]!
        let imageBlock = childFrame.blocks.first { $0.text == nil }!
        #expect(placed.imagePayloads[imageBlock.blockId] != nil)
    }

    @Test func smallImage_centered_whenTextDrivesWidth() {
        var doc = MindMapDocument.blank(rootText: "相当长的文字内容决定节点宽度")
        doc.root = Node(text: "相当长的文字内容决定节点宽度", image: Data([0x01]), imagePixelSize: ImagePixelSize(width: 50, height: 50))
        let placed = RadialLayout.place(document: doc, measure: measure())
        let frame = placed.frames[doc.root.id]!
        let imageBlocks = frame.blocks.filter { $0.text == nil }
        #expect(imageBlocks.count == 1)
        let rect = imageBlocks[0].rect
        #expect(rect.width == 50)
        #expect(abs(rect.midX - frame.size.width / 2) < 0.001)
    }

    @Test func imageBlock_topAligned_likeOldImageRect() {
        // 旧观感：imageRect y=0 贴顶（无 vPad）；文字在图片下方，文本顶 = 图底 + gap + vPad。
        var doc = MindMapDocument.blank(rootText: "根")
        doc.root = Node(
            text: "根",
            image: Data([0x01]),
            imagePixelSize: ImagePixelSize(width: 100, height: 50)
        )
        let placed = RadialLayout.place(document: doc, measure: measure())
        let frame = placed.frames[doc.root.id]!
        #expect(frame.blocks.count == 2)
        #expect(frame.blocks[0].text == nil)
        #expect(frame.blocks[0].rect.minY == 0)
        #expect(
            frame.blocks[1].rect.minY
                == frame.blocks[0].rect.height + LayoutConstants.imageTextGap + LayoutConstants.rootPadY
        )
    }

    @Test func imagelessNode_hasNoImageBlocksOrPayload() {
        let doc = MindMapDocument.blank(rootText: "根")
        let placed = RadialLayout.place(document: doc, measure: measure())
        #expect(placed.frames[doc.root.id]!.blocks.allSatisfy { $0.text != nil })
        #expect(placed.imagePayloads.isEmpty)
    }

    @Test func collapsedDescendantWithImage_isAbsentFromFramesAndPayloads() {
        var doc = MindMapDocument.blank(rootText: "根")
        let child = Node(text: "折叠", image: Data([0x01]), imagePixelSize: ImagePixelSize(width: 10, height: 10))
        doc.root.children = [child]
        doc.root.collapsedLeft = true
        doc.root.collapsedRight = true
        let placed = RadialLayout.place(document: doc, measure: measure())
        #expect(placed.frames[child.id] == nil)
        #expect(placed.imagePayloads[child.id] == nil)
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
        let placed = RadialLayout.place(document: doc, measure: measure())
        let frame = placed.frames[root]!
        let blocks = frame.blocks
        #expect(blocks.count == 3)
        #expect(blocks[0].text == "文")
        #expect(blocks[1].text == nil)
        #expect(blocks[2].text == "尾")
        #expect(blocks[1].rect.minY >= blocks[0].rect.maxY)
        #expect(blocks[2].rect.minY >= blocks[1].rect.maxY)
    }
}
