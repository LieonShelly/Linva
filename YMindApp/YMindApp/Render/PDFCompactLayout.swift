// Render/PDFCompactLayout.swift
import CoreGraphics
import Foundation

/// PDF 专用紧凑布局：左→右分层 tidy 树。
///
/// 画布用中心辐射布局；纸面导出用本布局，解决大树辐射包围盒
/// 「极窄极高（实测 2185 节点：宽 1925pt × 高 40808pt）」导致 A4
/// 网格切分后大量空白页、结构被切碎的问题。
///
/// 规则：
/// - 根在最左列，按深度向右分层（x = 累积层宽 + 层间距 hGap）
/// - 层内节点纵向排布：后序算子树垂直跨度，父 y 居中于子块中心
/// - 无重叠、父子兄弟关系连续；页序（列优先分页）≈ 根 → 叶
/// - 不缩放、文字可读；宽度受各层最宽节点约束，高度 = 树的总垂直跨度
struct PDFCompactLayout {
    static let hGap: CGFloat = 36   // 层间距（水平）
    static let vGap: CGFloat = 10   // 子节点垂直间距

    static func layout(document: MindMapDocument, measure: TextMeasure) -> LayoutSnapshot {
        let root = document.root

        // 1. 量尺寸 + 记录深度与每层最大宽
        var sizes: [UUID: NodeSize] = [:]
        var depths: [UUID: Int] = [:]
        var layerMaxW: [Int: CGFloat] = [:]
        var maxDepth = 0

        func measureAll(_ node: Node, depth: Int, isRoot: Bool) {
            let size = measure.size(for: node, isRoot: isRoot)
            sizes[node.id] = size
            depths[node.id] = depth
            layerMaxW[depth] = max(layerMaxW[depth] ?? 0, size.width)
            maxDepth = max(maxDepth, depth)
            node.children.forEach { measureAll($0, depth: depth + 1, isRoot: false) }
        }
        measureAll(root, depth: 0, isRoot: true)

        // 2. 层 x（左对齐：每层 x = 前层 x + 前层最宽 + hGap）
        var layerX: [Int: CGFloat] = [0: 0]
        for d in 1...maxDepth {
            layerX[d] = layerX[d - 1]! + (layerMaxW[d - 1] ?? 0) + hGap
        }

        // 3. 后序：每节点子树垂直半高（以节点 center 为锚）
        var subtreeHalfH: [UUID: CGFloat] = [:]

        func computeHalfH(_ node: Node) -> CGFloat {
            guard !node.children.isEmpty else {
                let half = sizes[node.id]!.height / 2
                subtreeHalfH[node.id] = half
                return half
            }
            let childHalfs = node.children.map { computeHalfH($0) }
            let total = childHalfs.reduce(0) { $0 + $1 * 2 }
                + vGap * CGFloat(node.children.count - 1)
            let half = max(sizes[node.id]!.height / 2, total / 2)
            subtreeHalfH[node.id] = half
            return half
        }
        _ = computeHalfH(root)

        // 4. 前序：绝对坐标（根 yCenter=0；子块居中于父 center）
        var frames: [UUID: NodeFrame] = [:]
        var edges: [EdgeGeometry] = []

        func place(
            _ node: Node,
            yCenter: CGFloat,
            isRoot: Bool,
            parentFrame: NodeFrame?
        ) {
            let size = sizes[node.id]!
            let x = layerX[depths[node.id]!]!
            let frame = NodeFrame(
                id: node.id,
                text: node.text,
                center: CGPoint(x: x + size.width / 2, y: yCenter),
                size: size,
                isRoot: isRoot,
                side: isRoot ? nil : .right,
                collapsed: node.collapsed,
                hiddenCount: node.collapsed ? 0 : 0,
                fill: node.fill
            )
            frames[node.id] = frame

            if let pf = parentFrame {
                // 肘形边：父右缘中 → 子左缘中（水平中段折转）
                let start = CGPoint(x: pf.center.x + pf.size.width / 2, y: pf.center.y)
                let end = CGPoint(x: frame.center.x - frame.size.width / 2, y: frame.center.y)
                let midX = (start.x + end.x) / 2
                edges.append(EdgeGeometry(
                    fromId: pf.id,
                    toId: frame.id,
                    side: .right,
                    points: [
                        start,
                        CGPoint(x: midX, y: start.y),
                        CGPoint(x: midX, y: end.y),
                        end,
                    ]
                ))
            }

            guard !node.children.isEmpty else { return }
            let childHalfs = node.children.map { subtreeHalfH[$0.id]! }
            let total = childHalfs.reduce(0) { $0 + $1 * 2 }
                + vGap * CGFloat(node.children.count - 1)
            var y = yCenter - total / 2
            for (i, child) in node.children.enumerated() {
                let childCenter = y + childHalfs[i]
                place(child, yCenter: childCenter, isRoot: false, parentFrame: frame)
                y += childHalfs[i] * 2 + vGap
            }
        }
        place(root, yCenter: 0, isRoot: true, parentFrame: nil)

        return LayoutSnapshot(frames: frames, edges: edges)
    }
}
