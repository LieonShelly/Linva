import CoreGraphics
import Foundation

struct NodeFrame: Equatable {
    let id: UUID
    let center: CGPoint
    let size: NodeSize
    let isRoot: Bool
    let side: Side?
    let collapsed: Bool
    let hiddenCount: Int

    var rect: CGRect {
        CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

struct EdgeGeometry: Equatable {
    let fromId: UUID
    let toId: UUID
    let side: Side
    let points: [CGPoint]
}

struct LayoutSnapshot: Equatable {
    let frames: [UUID: NodeFrame]
    let edges: [EdgeGeometry]
}
