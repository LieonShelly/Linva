import Foundation

/// 布局引擎抽象（DIP）：加第二种布局（组织图等）时替换类型。协议静态方法，RadialLayout 已具同签名。
protocol LayoutEngine {
    static func layout(document: MindMapDocument, measure: TextMeasure) -> LayoutSnapshot
}
