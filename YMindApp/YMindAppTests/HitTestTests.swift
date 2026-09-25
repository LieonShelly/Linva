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

    @Test func hitTest_prefersBranchToggleOverNode() {
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
