import Foundation

/// 节点内容块：文本或图片。块级 UUID 持久化（图片选中/删除/替换/Undo 按块 id 寻址）。
struct ContentBlock: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    var kind: Kind

    enum Kind: Codable, Equatable, Sendable {
        case text(String)
        case image(BlockImage)
    }

    struct BlockImage: Codable, Equatable, Sendable {
        var data: Data
        var pixelSize: ImagePixelSize
    }
}
