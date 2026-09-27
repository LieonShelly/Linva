import CoreGraphics
import Foundation

struct NodeFrame: Equatable {
    let id: UUID
    let text: String
    let center: CGPoint
    let size: NodeSize
    let isRoot: Bool
    let side: Side?
    let collapsed: Bool
    let hiddenCount: Int
    let fill: NodeFill?

    init(
        id: UUID,
        text: String,
        center: CGPoint,
        size: NodeSize,
        isRoot: Bool,
        side: Side?,
        collapsed: Bool,
        hiddenCount: Int,
        fill: NodeFill? = nil
    ) {
        self.id = id
        self.text = text
        self.center = center
        self.size = size
        self.isRoot = isRoot
        self.side = side
        self.collapsed = collapsed
        self.hiddenCount = hiddenCount
        self.fill = fill
    }

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

struct BranchToggle: Equatable {
    let nodeId: UUID
    let side: Side
    let center: CGPoint
    let collapsed: Bool
    let hiddenCount: Int
}

struct LayoutSnapshot: Equatable {
    let frames: [UUID: NodeFrame]
    let edges: [EdgeGeometry]
    let branchToggles: [BranchToggle]

    init(
        frames: [UUID: NodeFrame],
        edges: [EdgeGeometry],
        branchToggles: [BranchToggle] = []
    ) {
        self.frames = frames
        self.edges = edges
        self.branchToggles = branchToggles
    }
}
