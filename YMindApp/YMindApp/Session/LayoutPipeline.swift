import Foundation

/// 布局子域（SRP）：持量字器 + 布局引擎类型，产出 LayoutSnapshot。
final class LayoutPipeline {
    private let layoutEngineType: LayoutEngine.Type
    private let measure: TextMeasure

    init(layoutEngineType: LayoutEngine.Type = RadialLayout.self, measure: TextMeasure = TextMeasure()) {
        self.layoutEngineType = layoutEngineType
        self.measure = measure
    }

    func relayout(document: MindMapDocument) -> LayoutSnapshot {
        layoutEngineType.layout(document: document, measure: measure)
    }
}
