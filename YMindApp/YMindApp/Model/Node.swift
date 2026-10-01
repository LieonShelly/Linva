import Foundation

struct Node: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var text: String
    var collapsed: Bool
    var side: Side?
    var fill: NodeFill?
    var image: Data?
    var imagePixelSize: ImagePixelSize?
    var children: [Node]

    init(
        id: UUID = UUID(),
        text: String,
        collapsed: Bool = false,
        side: Side? = nil,
        fill: NodeFill? = nil,
        image: Data? = nil,
        imagePixelSize: ImagePixelSize? = nil,
        children: [Node] = []
    ) {
        self.id = id
        self.text = text
        self.collapsed = collapsed
        self.side = side
        self.fill = fill
        self.image = image
        self.imagePixelSize = imagePixelSize
        self.children = children
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, collapsed, side, fill, image, imagePixelSize, children
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        side = try c.decodeIfPresent(Side.self, forKey: .side)
        if let raw = try c.decodeIfPresent(String.self, forKey: .fill),
           let fill = NodeFill(rawValue: raw) {
            self.fill = fill
        } else {
            self.fill = nil
        }
        image = try c.decodeIfPresent(Data.self, forKey: .image)
        // 容错：宽高非法（<=0 或非有限）→ 视为无图片尺寸，不拒文件。
        // ImagePixelSize 的 failable init 不参与 Codable 合成，须在此显式校验。
        do {
            imagePixelSize = try c.decodeIfPresent(ImagePixelSize.self, forKey: .imagePixelSize)
            if let ps = imagePixelSize, !(ps.width > 0 && ps.height > 0 && ps.width.isFinite && ps.height.isFinite) {
                imagePixelSize = nil
            }
        } catch {
            imagePixelSize = nil
        }
        children = try c.decodeIfPresent([Node].self, forKey: .children) ?? []
    }
}
