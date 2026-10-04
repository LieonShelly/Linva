import Foundation

/// 布局引擎抽象（DIP）：加第二种布局（组织图等）时替换类型。协议静态方法，RadialLayout/LogicLayout 已具同签名。
/// 引擎只产排布（frames/toggles/imagePayloads）；连线几何由 EdgeStyleProvider 负责（D7）。
protocol LayoutEngine {
    static func place(
        document: MindMapDocument,
        measure: TextMeasure
    ) -> (frames: [UUID: NodeFrame], branchToggles: [BranchToggle], imagePayloads: [UUID: ImagePayload])
}
