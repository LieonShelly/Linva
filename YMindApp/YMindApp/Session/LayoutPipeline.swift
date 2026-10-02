import Foundation

/// 布局子域（SRP）：持量字器，按文档布局类型分派引擎，产出 LayoutSnapshot。
/// 换布局只改 `document.layout`，`relayout()` 单点自动生效。
final class LayoutPipeline {
    private let measure: TextMeasure

    init(measure: TextMeasure = TextMeasure()) {
        self.measure = measure
    }

    func relayout(document: MindMapDocument) -> LayoutSnapshot {
        switch document.layout {
        case .radial:
            return RadialLayout.layout(document: document, measure: measure)
        case .logic:
            return LogicLayout.layout(document: document, measure: measure)
        }
    }
}
