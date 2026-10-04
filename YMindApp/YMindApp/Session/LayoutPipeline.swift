import Foundation

/// 布局子域（SRP）：持量字器，按文档有效排布分派引擎 + 连线样式 Provider，产出 LayoutSnapshot。
/// 换布局只改 `document.layout`，换连线样式只改 `document.edgeStyle`（D7），`relayout()` 单点自动生效。
final class LayoutPipeline {
    private let measure: TextMeasure

    init(measure: TextMeasure = TextMeasure()) {
        self.measure = measure
    }

    func relayout(document: MindMapDocument) -> LayoutSnapshot {
        // D7：连线样式决定有效排布（brace 强制逻辑树）与 Connector 几何。
        let provider = EdgeStyleRegistry.provider(for: document.edgeStyle)
        let arrangement: LayoutKind = provider.requiresLogicArrangement ? .logic : document.layout
        let placed: (frames: [UUID: NodeFrame], branchToggles: [BranchToggle], imagePayloads: [UUID: ImagePayload])
        switch arrangement {
        case .radial:
            placed = RadialLayout.place(document: document, measure: measure)
        case .logic:
            placed = LogicLayout.place(document: document, measure: measure)
        }
        let connectors = provider.connectors(
            document: document,
            frames: placed.frames,
            root: document.root,
            measure: measure
        )
        return LayoutSnapshot(
            frames: placed.frames,
            connectors: connectors,
            branchToggles: placed.branchToggles,
            imagePayloads: placed.imagePayloads
        )
    }
}
