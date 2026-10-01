import Foundation

struct MindMapDocument: Equatable, Codable, Sendable {
    static let currentVersion = 3
    var version: Int
    var root: Node

    static func blank(rootText: String = "中心主题") -> MindMapDocument {
        MindMapDocument(version: currentVersion, root: Node(text: rootText))
    }
}
