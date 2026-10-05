import CoreGraphics
import Foundation

/// 连线的水平方向（frame 排布侧）：左 → -1，其余 → +1。
private func sideDir(_ side: Side?) -> CGFloat {
    side == .left ? -1 : 1
}

/// per-edge 样式（elbow/curve/straight）共用的父子遍历：每对有 frame 的父子产一个 Connector，
/// 边几何按 `style` 走 LayoutSupport.edgePoints 基元。方向取子 frame.side
/// （排布侧，孙继承父 side；模型节点 side 可为 nil）。
/// `elbowFoldAtChildX`：logic 排布下 elbow 竖折在子节点 x（to.x），恢复 pre-feature 外观
/// （PRD §6 #5 保持现状）；radial 走 edgePoints 中点基元。仅 ElbowProvider 传 true。
/// internal：跨 Provider 文件共享（新 per-edge 样式直接复用，勿复制遍历）。
func perEdgeConnectors(
    style: EdgeStyle,
    frames: [UUID: NodeFrame],
    root: Node,
    elbowFoldAtChildX: Bool = false
) -> [ConnectorGeometry] {
    var out: [ConnectorGeometry] = []
    func walk(_ node: Node) {
        guard let pf = frames[node.id] else { return }
        for child in node.children {
            if let cf = frames[child.id] {
                let dir = sideDir(cf.side)
                let start = CGPoint(x: pf.center.x + dir * pf.size.width / 2, y: pf.center.y)
                let end = CGPoint(x: cf.center.x - dir * cf.size.width / 2, y: cf.center.y)
                let path = elbowFoldAtChildX
                    ? LayoutSupport.logicElbow(from: start, to: end)
                    : LayoutSupport.edgePoints(from: start, to: end, style: style)
                out.append(ConnectorGeometry(
                    id: child.id,
                    path: path,
                    marker: nil,
                    fromId: node.id,
                    toId: child.id
                ))
            }
            walk(child)
        }
    }
    walk(root)
    return out
}

/// 折线样式（D1）：正交折线。radial 竖折中点 mx=(from.x+to.x)/2；
/// logic（总分树）竖折在子节点 x（to.x），保持 pre-feature 默认外观（PRD §6 #5）。
struct ElbowProvider: EdgeStyleProvider {
    var requiresLogicArrangement: Bool { false }
    func connectors(
        document: MindMapDocument,
        frames: [UUID: NodeFrame],
        root: Node,
        measure: TextMeasure
    ) -> [ConnectorGeometry] {
        perEdgeConnectors(
            style: .elbow,
            frames: frames,
            root: root,
            elbowFoldAtChildX: document.layout == .logic
        )
    }
}

/// 曲线样式（D1）：水平切向 S 曲线采样（垂直主导边用垂直切向），每边一条。
struct CurveProvider: EdgeStyleProvider {
    var requiresLogicArrangement: Bool { false }
    func connectors(
        document: MindMapDocument,
        frames: [UUID: NodeFrame],
        root: Node,
        measure: TextMeasure
    ) -> [ConnectorGeometry] {
        perEdgeConnectors(style: .curve, frames: frames, root: root)
    }
}

/// 大括号样式（D2/D3）：父-组连接器，每有子的父一个 "}"，子不连边。
struct BraceProvider: EdgeStyleProvider {
    var requiresLogicArrangement: Bool { true }
    /// 产组括号 Connector（每有子父节点一个）。
    /// - 前置条件：`frames` 必须按逻辑树排布（父左子右、子竖排自上而下）——首子 topmost。
    ///   `buildBrace` 取 yTop=首子 center.y、yBottom=末子 center.y，靠首末子垂直顺序
    ///   保证 yTop ≤ yBottom（r = min(..., (yBottom−yTop)/4) 为正）；乱序会使 r 为负、弧反向。
    /// - 该前置由 LayoutPipeline 保证：brace 的 `requiresLogicArrangement == true` 强制走
    ///   LogicLayout 排布，再调本方法产 Connector。
    func connectors(
        document: MindMapDocument,
        frames: [UUID: NodeFrame],
        root: Node,
        measure: TextMeasure
    ) -> [ConnectorGeometry] {
        var out: [ConnectorGeometry] = []
        func brace(_ node: Node) {
            let kids = node.children
            guard !kids.isEmpty,
                  let pf = frames[node.id],
                  let fc = frames[kids[0].id],
                  let lc = frames[kids[kids.count - 1].id] else { return }
            let isMain = node.id == root.id
            // 根/子括号嘴均不带圆圈标记（用户要求）；hasCircle 保留为 addendum §3
            // 未来「折叠/选中圆圈」的预留钩子，当前恒 false。
            out.append(Self.buildBrace(
                id: node.id,
                parent: pf,
                first: fc,
                last: lc,
                childCount: kids.count,
                isMain: isMain,
                hasCircle: false
            ))
            for k in kids { brace(k) }
        }
        brace(root)
        return out
    }

    /// 按参考 HTML（gemini-code-…html）构建一个开口 "}" 组括号 Connector。
    /// - 嘴（尖角）Y 对齐父节点垂直中心（"头对齐父节点"）：yMid = parent.center.y。
    /// - 开口不封闭：单条连续折线 右上端点 → 上弧 → spine 上段 → 嘴 → spine 下段 → 下弧 → 右下端点，
    ///   xRight 上下两端开口，无右缘竖线、无父→嘴短直线（参考 HTML 同）。
    /// - 上弧/下弧按 Q/L 段采样成折线；嘴为 path 内部点（非首/末）。
    /// - 根带圆圈时：xTip=mouthX+15，并产 ConnectorMarker(.circle, (xTip−4.5−1, yMid), 4.5)。
    static func buildBrace(
        id: UUID,
        parent: NodeFrame,
        first: NodeFrame,
        last: NodeFrame,
        childCount: Int,
        isMain: Bool,
        hasCircle: Bool
    ) -> ConnectorGeometry {
        let yTop: CGFloat
        let yBottom: CGFloat
        if childCount == 1 {
            let span = max(first.size.height * 0.85, 28)
            yTop = first.center.y - span / 2
            yBottom = first.center.y + span / 2
        } else {
            yTop = first.center.y
            yBottom = last.center.y
        }
        // 嘴（尖角）Y 对齐父节点垂直中心，而非首末子中点——保证 "头对齐父节点"。
        let yMid = parent.center.y
        let w: CGFloat = isMain ? 56 : 34
        let mouthX = parent.rect.maxX
        let xTip = mouthX + (hasCircle ? 15 : 10)
        let xStem = mouthX + w * 0.54
        let xRight = mouthX + w - 8
        let r = min(16, (yBottom - yTop) / 4, xRight - xStem, xStem - xTip)

        var pts: [CGPoint] = []
        // 开口 "}"：右上端点 → 上弧 → spine 上段 → 嘴 → spine 下段 → 下弧 → 右下端点（xRight 两端开口）。
        // 参考 HTML path：
        //   M xRight yTop Q xStem yTop, xStem yTop+r L xStem yMid−r Q xStem yMid, xTip yMid
        //   Q xStem yMid, xStem yMid+r L xStem yBottom−r Q xStem yBottom, xRight yBottom
        pts.append(CGPoint(x: xRight, y: yTop))
        sampleQuad(into: &pts,
                   from: CGPoint(x: xRight, y: yTop),
                   control: CGPoint(x: xStem, y: yTop),
                   to: CGPoint(x: xStem, y: yTop + r))
        pts.append(CGPoint(x: xStem, y: yMid - r))
        sampleQuad(into: &pts,
                   from: CGPoint(x: xStem, y: yMid - r),
                   control: CGPoint(x: xStem, y: yMid),
                   to: CGPoint(x: xTip, y: yMid))
        sampleQuad(into: &pts,
                   from: CGPoint(x: xTip, y: yMid),
                   control: CGPoint(x: xStem, y: yMid),
                   to: CGPoint(x: xStem, y: yMid + r))
        pts.append(CGPoint(x: xStem, y: yBottom - r))
        sampleQuad(into: &pts,
                   from: CGPoint(x: xStem, y: yBottom - r),
                   control: CGPoint(x: xStem, y: yBottom),
                   to: CGPoint(x: xRight, y: yBottom))

        let marker: ConnectorMarker? = hasCircle
            ? ConnectorMarker(kind: .circle, center: CGPoint(x: xTip - 4.5 - 1, y: yMid), radius: 4.5)
            : nil
        return ConnectorGeometry(id: id, path: pts, marker: marker, fromId: parent.id, toId: parent.id)
    }

    /// 二次贝塞尔采样（Bernstein），含终点（起点由调用方已入列）；每弧 10 段。
    private static func sampleQuad(
        into pts: inout [CGPoint],
        from p0: CGPoint,
        control c: CGPoint,
        to p1: CGPoint,
        segments: Int = 10
    ) {
        for i in 1...segments {
            let t = CGFloat(i) / CGFloat(segments)
            let u = 1 - t
            pts.append(CGPoint(
                x: u*u*p0.x + 2*u*t*c.x + t*t*p1.x,
                y: u*u*p0.y + 2*u*t*c.y + t*t*p1.y
            ))
        }
    }
}
