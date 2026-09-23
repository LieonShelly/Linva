import Foundation

struct Node: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var text: String
    var collapsed: Bool
    var side: Side?
    var children: [Node]

    init(
        id: UUID = UUID(),
        text: String,
        collapsed: Bool = false,
        side: Side? = nil,
        children: [Node] = []
    ) {
        self.id = id
        self.text = text
        self.collapsed = collapsed
        self.side = side
        self.children = children
    }
}
