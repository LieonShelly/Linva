import CoreGraphics
import Foundation

/// 块布局帧：文本块带内容，图片块 text 为 nil。rect 为节点局部坐标 top-left 原点。
struct BlockLayoutFrame: Equatable {
    let blockId: UUID
    let text: String?
    let rect: CGRect
}

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
    let blocks: [BlockLayoutFrame]

    init(
        id: UUID,
        text: String,
        center: CGPoint,
        size: NodeSize,
        isRoot: Bool,
        side: Side?,
        collapsed: Bool,
        hiddenCount: Int,
        fill: NodeFill? = nil,
        blocks: [BlockLayoutFrame] = []
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
        self.blocks = blocks
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

/// 连接器标记：在连接器某处绘制的小符号（如起点圆点）。
struct ConnectorMarker: Equatable {
    enum Kind: Equatable {
        case circle
    }
    let kind: Kind
    let center: CGPoint
    let radius: CGFloat
}

/// 统一连线契约：任何样式产一个可描边的连接器（path 折线 + 可选 marker）。
struct ConnectorGeometry: Equatable {
    let id: UUID
    let path: [CGPoint]
    let marker: ConnectorMarker?
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
    let connectors: [ConnectorGeometry]
    let branchToggles: [BranchToggle]
    let imagePayloads: [UUID: ImagePayload]

    init(
        frames: [UUID: NodeFrame],
        connectors: [ConnectorGeometry] = [],
        branchToggles: [BranchToggle] = [],
        imagePayloads: [UUID: ImagePayload] = [:]
    ) {
        self.frames = frames
        self.connectors = connectors
        self.branchToggles = branchToggles
        self.imagePayloads = imagePayloads
    }
}

/// 有图节点的图片载荷：Layout 从 Model 拷出像素数据与尺寸，Render 只消费 Snapshot。
struct ImagePayload: Equatable {
    let pixelSize: ImagePixelSize
    let data: Data
}
