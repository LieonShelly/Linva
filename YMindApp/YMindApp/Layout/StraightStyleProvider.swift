import CoreGraphics
import Foundation

/// 直线样式（回归验证 D7 扩展性）：父-子两点直线 Connector。
/// 加样式只动「enum case + Provider 文件 + registry 注册 + edgePoints 基元 case」，
/// 引擎 / Render / Codec 零改动。此样式仅验证机制，不暴露于最终 UI 三选一。
struct StraightStyleProvider: EdgeStyleProvider {
    var requiresLogicArrangement: Bool { false }
    func connectors(
        document: MindMapDocument,
        frames: [UUID: NodeFrame],
        root: Node,
        measure: TextMeasure
    ) -> [ConnectorGeometry] {
        // 复用共享 per-edge 遍历；边几何走 edgePoints(.straight) = [from, to] 两点直线。
        perEdgeConnectors(style: .straight, frames: frames, root: root)
    }
}
