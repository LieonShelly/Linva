import Foundation

struct Node: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var blocks: [ContentBlock]
    var collapsed: Bool
    /// 根节点左右两侧的独立折叠态（仅根使用；非根恒为 false，sanitize 强制）。
    var collapsedLeft: Bool
    var collapsedRight: Bool
    var side: Side?
    var fill: NodeFill?
    var children: [Node]

    init(
        id: UUID = UUID(),
        text: String,
        collapsed: Bool = false,
        collapsedLeft: Bool = false,
        collapsedRight: Bool = false,
        side: Side? = nil,
        fill: NodeFill? = nil,
        image: Data? = nil,
        imagePixelSize: ImagePixelSize? = nil,
        children: [Node] = []
    ) {
        self.id = id
        if let image, let imagePixelSize {
            // 构造兼容：旧单图形态 → 图在上、文在下（保持旧视觉）。
            self.blocks = [
                ContentBlock(id: UUID(), kind: .image(.init(data: image, pixelSize: imagePixelSize))),
                ContentBlock(id: UUID(), kind: .text(text)),
            ]
        } else {
            self.blocks = [ContentBlock(id: UUID(), kind: .text(text))]
        }
        self.collapsed = collapsed
        self.collapsedLeft = collapsedLeft
        self.collapsedRight = collapsedRight
        self.side = side
        self.fill = fill
        self.children = children
    }

    /// 只读兼容：文本块按序以 "\n" 连接（搜索/编辑 draft/导出标题零改动）。
    var text: String {
        blocks.compactMap { if case .text(let s) = $0.kind { s } else { nil } }.joined(separator: "\n")
    }

    /// 只读兼容：首个图片块数据（单图读方零改动；多图读方走 blocks）。
    var image: Data? {
        for b in blocks {
            if case .image(let img) = b.kind { return img.data }
        }
        return nil
    }

    /// 只读兼容：与 `image` 同块。
    var imagePixelSize: ImagePixelSize? {
        for b in blocks {
            if case .image(let img) = b.kind { return img.pixelSize }
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, collapsed, collapsedLeft, collapsedRight, side, fill, image, imagePixelSize, blocks, children
    }

    func encode(to encoder: Encoder) throws {
        // v4：只写存储属性（blocks 为准）；text/image/imagePixelSize 是计算属性，不落盘。
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(blocks, forKey: .blocks)
        try c.encode(collapsed, forKey: .collapsed)
        try c.encode(collapsedLeft, forKey: .collapsedLeft)
        try c.encode(collapsedRight, forKey: .collapsedRight)
        try c.encodeIfPresent(side, forKey: .side)
        try c.encodeIfPresent(fill, forKey: .fill)
        try c.encode(children, forKey: .children)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        collapsedLeft = try c.decodeIfPresent(Bool.self, forKey: .collapsedLeft) ?? false
        collapsedRight = try c.decodeIfPresent(Bool.self, forKey: .collapsedRight) ?? false
        side = try c.decodeIfPresent(Side.self, forKey: .side)
        if let raw = try c.decodeIfPresent(String.self, forKey: .fill),
           let fill = NodeFill(rawValue: raw) {
            self.fill = fill
        } else {
            self.fill = nil
        }
        children = try c.decodeIfPresent([Node].self, forKey: .children) ?? []

        // v4：直接读 blocks。
        if let blocks = try c.decodeIfPresent([ContentBlock].self, forKey: .blocks) {
            self.blocks = blocks
            return
        }
        // v1/v2/v3 fallback：text + image/imagePixelSize → 合成块（图在上、文在下）。
        let text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        var blocks: [ContentBlock] = []
        if let image = try c.decodeIfPresent(Data.self, forKey: .image) {
            var px: ImagePixelSize? = nil
            do {
                px = try c.decodeIfPresent(ImagePixelSize.self, forKey: .imagePixelSize)
                if let ps = px, !(ps.width > 0 && ps.height > 0 && ps.width.isFinite && ps.height.isFinite) {
                    px = nil
                }
            } catch {
                px = nil
            }
            if let px {
                blocks.append(ContentBlock(id: UUID(), kind: .image(.init(data: image, pixelSize: px))))
            }
        }
        blocks.append(ContentBlock(id: UUID(), kind: .text(text)))
        self.blocks = blocks
    }
}
