import Foundation

/// 图片像素尺寸（归一器写入；Layout 只读此值，不解析 PNG 头）。
/// 自有类型原因：CGSize 在 `import Foundation` 下不可 Codable（实测），Model 白名单禁 CoreGraphics。
struct ImagePixelSize: Codable, Equatable, Sendable {
    let width: Double
    let height: Double

    init?(width: Double, height: Double) {
        guard width > 0, height > 0, width.isFinite, height.isFinite else { return nil }
        self.width = width
        self.height = height
    }
}
