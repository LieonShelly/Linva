import Foundation

/// 连线样式 → Provider 注册表（D7 单一分派点）。
/// 加新样式 = EdgeStyle 加 case + 新建 Provider 文件 + 此处注册；switch 仅存在于本文件。
enum EdgeStyleRegistry {
    static func provider(for style: EdgeStyle) -> EdgeStyleProvider {
        switch style {
        case .elbow: return ElbowProvider()
        case .curve: return CurveProvider()
        case .brace: return BraceProvider()
        case .straight: return StraightStyleProvider()
        }
    }
}
