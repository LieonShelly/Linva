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
            hitTest(
                screenPoint: camera.worldToScreen(frame.center),
                snapshot: snapshot,
                camera: camera
            ) == id
        )
        #expect(
            hitTest(
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
            hitTest(
                screenPoint: .zero,
                snapshot: snapshot,
                camera: Camera()
            ) == smallId
        )
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
