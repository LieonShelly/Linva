import Foundation

struct Node: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var text: String
    var collapsed: Bool
    var side: Side?
    var fill: NodeFill?
    var children: [Node]

    init(
        id: UUID = UUID(),
        text: String,
        collapsed: Bool = false,
        side: Side? = nil,
        fill: NodeFill? = nil,
        children: [Node] = []
    ) {
        self.id = id
        self.text = text
        self.collapsed = collapsed
        self.side = side
        self.fill = fill
        self.children = children
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, collapsed, side, fill, children
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
        children = try c.decodeIfPresent([Node].self, forKey: .children) ?? []
    }
}
