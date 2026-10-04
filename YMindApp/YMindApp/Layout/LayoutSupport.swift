import CoreGraphics
import Foundation

/// 布局共享的递归测高元数据：RadialLayout 与 LogicLayout 共用。
struct BranchMetadata {
    let size: NodeSize
    let height: CGFloat
    let blocks: [BlockLayoutFrame]
    let children: [BranchMetadata]
}

/// 布局共享辅助：测高 / 块映射 / toggle / 图片载荷，供两种布局引擎复用。
enum LayoutSupport {
    static func subtreeHeight(_ node: Node, isRoot: Bool, measure: TextMeasure) -> BranchMetadata {
        let m = measure.measure(for: node, isRoot: isRoot)
        let size = m.size
        guard !node.collapsed, !node.children.isEmpty else {
            return BranchMetadata(size: size, height: size.height, blocks: m.blocks, children: [])
        }
        let childLayouts = node.children.map { subtreeHeight($0, isRoot: false, measure: measure) }
        let childrenHeight = childLayouts.reduce(0) { $0 + $1.height }
            + LayoutConstants.vGap * CGFloat(childLayouts.count - 1)
        return BranchMetadata(
            size: size,
            height: max(size.height, childrenHeight),
            blocks: m.blocks,
            children: childLayouts
        )
    }

    /// 把测高时的块映射到节点局部坐标（top-left 原点）：文本块撑满整行宽，
    /// 非文本块水平居中。rect 为节点局部坐标，调用方再平移叠加节点位置。
    static func centeredBlocks(from metadata: BranchMetadata) -> [BlockLayoutFrame] {
        metadata.blocks.map { b -> BlockLayoutFrame in
            if b.text != nil {
                return BlockLayoutFrame(
                    blockId: b.blockId,
                    text: b.text,
                    rect: CGRect(x: 0, y: b.rect.minY, width: metadata.size.width, height: b.rect.height)
                )
            }
            return BlockLayoutFrame(
                blockId: b.blockId,
                text: nil,
                rect: CGRect(
                    x: (metadata.size.width - b.rect.width) / 2,
                    y: b.rect.minY,
                    width: b.rect.width,
                    height: b.rect.height
                )
            )
        }
    }

    static func countDescendants(_ node: Node) -> Int {
        node.children.reduce(0) { $0 + 1 + countDescendants($1) }
    }

    /// 根某一侧的后代数：只统计该侧子节点子树（用于根左右独立折叠的 hiddenCount）。
    static func countDescendants(_ node: Node, side: Side) -> Int {
        node.children
            .filter { side == .left ? $0.side == .left : $0.side != .left }
            .reduce(0) { $0 + 1 + countDescendants($1) }
    }

    static func makeToggle(node: Node, frame: NodeFrame, side: Side) -> BranchToggle {
        makeToggle(
            node: node,
            frame: frame,
            side: side,
            collapsed: node.collapsed,
            hiddenCount: node.collapsed ? countDescendants(node) : 0
        )
    }

    /// 显式折叠态版本：供根左右独立折叠 toggle 使用（每侧各自 collapsed/hiddenCount）。
    static func makeToggle(
        node: Node,
        frame: NodeFrame,
        side: Side,
        collapsed: Bool,
        hiddenCount: Int
    ) -> BranchToggle {
        let dir: CGFloat = side == .left ? -1 : 1
        return BranchToggle(
            nodeId: node.id,
            side: side,
            center: CGPoint(
                x: frame.center.x + dir * (frame.size.width / 2 + LayoutConstants.branchToggleGap),
                y: frame.center.y
            ),
            collapsed: collapsed,
            hiddenCount: hiddenCount
        )
    }

    static func collectImagePayloads(root: Node, frames: [UUID: NodeFrame]) -> [UUID: ImagePayload] {
        var payloads: [UUID: ImagePayload] = [:]
        func collect(_ node: Node) {
            for block in node.blocks {
                if case .image(let img) = block.kind, frames[node.id] != nil {
                    payloads[block.id] = ImagePayload(pixelSize: img.pixelSize, data: img.data)
                }
            }
            node.children.forEach(collect)
        }
        collect(root)
        return payloads
    }

    /// 每边样式的折线几何基元（spec §4.1，D1）：elbow 正交折线；curve 三次贝塞尔
    /// 切向 S 曲线采样；straight 两点直线。brace 是组样式，不走此基元（返回 []）。
    static func edgePoints(from: CGPoint, to: CGPoint, style: EdgeStyle) -> [CGPoint] {
        switch style {
        case .elbow:
            let mx = (from.x + to.x) / 2
            return [from, CGPoint(x: mx, y: from.y), CGPoint(x: mx, y: to.y), to]
        case .curve:
            let dx = to.x - from.x
            let dy = to.y - from.y
            if abs(dx) >= abs(dy) {
                // 水平主导：水平切向，k = clamp(|dx|·0.4, 18, 56)。
                let dir: CGFloat = dx >= 0 ? 1 : -1
                let k = max(18, min(56, abs(dx) * 0.4))
                return sampleCubic(
                    from,
                    CGPoint(x: from.x + dir * k, y: from.y),
                    CGPoint(x: to.x - dir * k, y: to.y),
                    to,
                    segments: 20
                )
            } else {
                // 垂直主导：垂直切向。
                let dir: CGFloat = dy >= 0 ? 1 : -1
                let k = max(18, min(56, abs(dy) * 0.4))
                return sampleCubic(
                    from,
                    CGPoint(x: from.x, y: from.y + dir * k),
                    CGPoint(x: to.x, y: to.y - dir * k),
                    to,
                    segments: 20
                )
            }
        case .brace:
            return []
        case .straight:
            return [from, to]
        }
    }

    /// 三次贝塞尔采样（Bernstein），含两端点，共 segments+1 点。
    static func sampleCubic(
        _ p0: CGPoint,
        _ c1: CGPoint,
        _ c2: CGPoint,
        _ p1: CGPoint,
        segments: Int
    ) -> [CGPoint] {
        var pts: [CGPoint] = []
        pts.reserveCapacity(segments + 1)
        for i in 0...segments {
            let t = CGFloat(i) / CGFloat(segments)
            let u = 1 - t
            pts.append(CGPoint(
                x: u*u*u*p0.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*p1.x,
                y: u*u*u*p0.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*p1.y
            ))
        }
        return pts
    }
}
