import CoreGraphics
import Foundation
import Testing
@testable import YMindApp

@Suite("画布命中")
struct HitTestTests {
    @Test func hitTest_convertsScreenPointToWorld() {
        let id = UUID()
        let frame = NodeFrame(
            id: id,
            text: "主题",
            center: CGPoint(x: 50, y: 30),
            size: NodeSize(width: 40, height: 20),
            isRoot: false,
            side: .right,
            collapsed: false,
            hiddenCount: 0
        )
        let snapshot = LayoutSnapshot(frames: [id: frame], edges: [])
        let camera = Camera(
            translation: CGPoint(x: 100, y: 80),
            scale: 2
        )

        #expect(
            hitTestNode(
                screenPoint: camera.worldToScreen(frame.center),
                snapshot: snapshot,
                camera: camera
            ) == id
        )
        #expect(
            hitTestNode(
                screenPoint: CGPoint(x: 0, y: 0),
                snapshot: snapshot,
                camera: camera
            ) == nil
        )
    }

    @Test func hitTest_prefersSmallestOverlappingFrame() {
        let largeId = UUID()
        let smallId = UUID()
        let large = makeFrame(id: largeId, size: NodeSize(width: 100, height: 100))
        let small = makeFrame(id: smallId, size: NodeSize(width: 20, height: 20))
        let snapshot = LayoutSnapshot(
            frames: [largeId: large, smallId: small],
            edges: []
        )

        #expect(
            hitTestNode(
                screenPoint: .zero,
                snapshot: snapshot,
                camera: Camera()
            ) == smallId
        )
    }

    @Test func hitTestCanvas_returnsNodeAndEmpty() {
        let id = UUID()
        let frame = makeFrame(id: id, size: NodeSize(width: 40, height: 20))
        let snapshot = LayoutSnapshot(frames: [id: frame], edges: [])

        #expect(
            hitTestCanvas(screenPoint: .zero, snapshot: snapshot, camera: Camera())
                == .node(id)
        )
        #expect(
            hitTestCanvas(
                screenPoint: CGPoint(x: 500, y: 500),
                snapshot: snapshot,
                camera: Camera()
            ) == .empty
        )
    }

    @Test func marqueeIntersectingIds_hitsOverlappingFramesOnly() {
        let a = UUID()
        let b = UUID()
        let fa = makeFrame(id: a, size: NodeSize(width: 20, height: 20))
        let fb = NodeFrame(
            id: b,
            text: "B",
            center: CGPoint(x: 100, y: 0),
            size: NodeSize(width: 20, height: 20),
            isRoot: false,
            side: .right,
            collapsed: false,
            hiddenCount: 0
        )
        let snapshot = LayoutSnapshot(frames: [a: fa, b: fb], edges: [])

        #expect(
            marqueeIntersectingIds(
                worldRect: CGRect(x: -5, y: -5, width: 30, height: 30),
                snapshot: snapshot
            ) == [a]
        )
        #expect(
            marqueeIntersectingIds(
                worldRect: CGRect(x: -200, y: -200, width: 400, height: 400),
                snapshot: snapshot
            ) == [a, b]
        )
    }

    @Test func hitTestCanvas_hitsBranchToggleAtFork() {
        let nodeId = UUID()
        let frame = NodeFrame(
            id: nodeId, text: "P", center: .zero,
            size: NodeSize(width: 80, height: 40),
            isRoot: false, side: .right,
            collapsed: false, hiddenCount: 0
        )
        let toggle = BranchToggle(
            nodeId: nodeId, side: .right,
            center: CGPoint(x: 58, y: 0),
            collapsed: false, hiddenCount: 0
        )
        let snapshot = LayoutSnapshot(
            frames: [nodeId: frame], edges: [], branchToggles: [toggle]
        )
        let hit = hitTestCanvas(
            screenPoint: CGPoint(x: 58, y: 0),
            snapshot: snapshot,
            camera: Camera()
        )
        #expect(hit == .branchToggle(nodeId: nodeId))
    }

    @Test func hitTestCanvas_coversWidenedCollapsedPillButKeepsNodeClickable() {
        let nodeId = UUID()
        let frame = NodeFrame(
            id: nodeId, text: "P", center: .zero,
            size: NodeSize(width: 80, height: 40),
            isRoot: false, side: .right,
            collapsed: true, hiddenCount: 12
        )
        let collapsedToggle = BranchToggle(
            nodeId: nodeId, side: .right,
            center: CGPoint(x: 58, y: 0),
            collapsed: true, hiddenCount: 12
        )
        let expandedToggle = BranchToggle(
            nodeId: nodeId, side: .right,
            center: CGPoint(x: 58, y: 0),
            collapsed: false, hiddenCount: 0
        )
        let collapsedSnapshot = LayoutSnapshot(
            frames: [nodeId: frame], edges: [], branchToggles: [collapsedToggle]
        )
        let expandedSnapshot = LayoutSnapshot(
            frames: [nodeId: frame], edges: [], branchToggles: [expandedToggle]
        )

        // 「−12」把胶囊加宽到 15，其末端必须仍可命中。
        #expect(
            hitTestCanvas(
                screenPoint: CGPoint(x: 43.5, y: 0),
                snapshot: collapsedSnapshot,
                camera: Camera()
            ) == .branchToggle(nodeId: nodeId)
        )
        // 同一位置在未加宽（＋）时属于空白。
        #expect(
            hitTestCanvas(
                screenPoint: CGPoint(x: 43.5, y: 0),
                snapshot: expandedSnapshot,
                camera: Camera()
            ) == .empty
        )
        // 节点内部仍归节点。
        #expect(
            hitTestCanvas(
                screenPoint: CGPoint(x: 20, y: 0),
                snapshot: collapsedSnapshot,
                camera: Camera()
            ) == .node(nodeId)
        )
    }

    @Test func hitTestCanvas_prefersBranchToggleWhenRegionsOverlap() {
        let nodeId = UUID()
        let frame = makeFrame(id: nodeId, size: NodeSize(width: 80, height: 40))
        let overlapping = BranchToggle(
            nodeId: nodeId,
            side: .right,
            center: .zero,
            collapsed: false,
            hiddenCount: 0
        )
        let snapshot = LayoutSnapshot(
            frames: [nodeId: frame], edges: [], branchToggles: [overlapping]
        )

        #expect(
            hitTestCanvas(screenPoint: .zero, snapshot: snapshot, camera: Camera())
                == .branchToggle(nodeId: nodeId)
        )
    }

    @Test func branchToggleHit_coversWholePill_withoutReachingNode() {
        let nodeId = UUID()
        // 节点宽 80 → 边缘在 ±40；控件中心按 gap=18 落在 ±58。
        for hiddenCount in [0, 4, 12, 123, 99999] {
            let toggle = BranchToggle(
                nodeId: nodeId,
                side: .right,
                center: CGPoint(x: 58, y: 0),
                collapsed: hiddenCount > 0,
                hiddenCount: hiddenCount
            )
            let pill = branchToggleWorldRect(toggle)

            #expect(branchToggleHitContains(toggle, worldPoint: CGPoint(x: pill.minX, y: 0)))
            #expect(branchToggleHitContains(toggle, worldPoint: CGPoint(x: pill.maxX, y: 0)))
            #expect(!branchToggleHitContains(toggle, worldPoint: CGPoint(x: 40 - 0.001, y: 0)))
            #expect(!branchToggleHitContains(toggle, worldPoint: CGPoint(x: 58, y: 14.001)))
        }
    }

    private func makeFrame(id: UUID, size: NodeSize) -> NodeFrame {
        NodeFrame(
            id: id,
            text: "主题",
            center: .zero,
            size: size,
            isRoot: false,
            side: .right,
            collapsed: false,
            hiddenCount: 0
        )
    }
}

@Suite("图片命中")
struct ImageHitTests {
    @Test func hitTestImageBlock_insideImage_returnsNodeAndBlock() {
        let id = UUID()
        let blockId = UUID()
        let frame = NodeFrame(
            id: id, text: "主题", center: .zero, size: NodeSize(width: 100, height: 100),
            isRoot: false, side: .right, collapsed: false, hiddenCount: 0,
            blocks: [
                BlockLayoutFrame(
                    blockId: blockId,
                    text: nil,
                    rect: CGRect(x: 0, y: 0, width: 100, height: 50)   // 节点上半
                ),
            ]
        )
        let snapshot = LayoutSnapshot(frames: [id: frame], edges: [])
        let camera = Camera()
        // 块 rect top-left 原点：世界 rect = frame.rect.min + local 偏移
        let worldRect = CGRect(
            x: frame.rect.minX, y: frame.rect.minY, width: 100, height: 50)
        let screenPoint = camera.worldToScreen(CGPoint(x: worldRect.midX, y: worldRect.midY))
        let hit = hitTestImageBlock(screenPoint: screenPoint, snapshot: snapshot, camera: camera)
        #expect(hit?.nodeId == id)
        #expect(hit?.blockId == blockId)
        // 文字区（下半）不算图片
        let textPoint = camera.worldToScreen(CGPoint(x: frame.rect.midX, y: frame.rect.maxY - 5))
        #expect(hitTestImageBlock(screenPoint: textPoint, snapshot: snapshot, camera: camera) == nil)
    }

    @Test func hitTestImageBlock_outsideNode_returnsNil() {
        let id = UUID()
        let frame = NodeFrame(
            id: id, text: "n", center: .zero, size: NodeSize(width: 80, height: 40),
            isRoot: false, side: .right, collapsed: false, hiddenCount: 0,
            blocks: [
                BlockLayoutFrame(
                    blockId: UUID(),
                    text: nil,
                    rect: CGRect(x: 0, y: 0, width: 80, height: 20)
                ),
            ]
        )
        let snapshot = LayoutSnapshot(frames: [id: frame], edges: [])
        #expect(hitTestImageBlock(screenPoint: CGPoint(x: 500, y: 500), snapshot: snapshot, camera: Camera()) == nil)
    }
}
