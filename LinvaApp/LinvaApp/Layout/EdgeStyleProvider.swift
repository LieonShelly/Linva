import CoreGraphics
import Foundation

/// 连线样式扩展点（D7）：每种样式一个 Provider，负责产该样式的 Connector 几何。
/// 加新样式 = EdgeStyle 加 case + 新建 Provider 文件 + EdgeStyleRegistry 注册，
/// 引擎 / Render / Codec 零改动。
protocol EdgeStyleProvider {
    /// 是否需要逻辑树排布（brace=true；per-edge 样式=false）。
    var requiresLogicArrangement: Bool { get }
    /// 按排布结果（frames）产该样式的全部 Connector（含可选 marker）。
    func connectors(
        document: MindMapDocument,
        frames: [UUID: NodeFrame],
        root: Node,
        measure: TextMeasure
    ) -> [ConnectorGeometry]
}

/// 占位 Provider（测试哨兵）：registry 不得返回它。
struct EmptyProvider: EdgeStyleProvider {
    var requiresLogicArrangement: Bool { false }
    func connectors(
        document: MindMapDocument,
        frames: [UUID: NodeFrame],
        root: Node,
        measure: TextMeasure
    ) -> [ConnectorGeometry] { [] }
}
