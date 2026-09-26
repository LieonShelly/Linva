import Foundation

enum MindMapCommand: Equatable {
    case addChild(parentId: UUID, text: String)
    case addSibling(selectedId: UUID, text: String)
    case delete(ids: [UUID])
    case setText(id: UUID, old: String, new: String)
    case toggleCollapse(id: UUID)
    case setCollapsed(ids: [UUID], collapsed: Bool)
    case moveToParent(ids: [UUID], parentId: UUID)
    case insertSiblings(ids: [UUID], anchorId: UUID, position: BeforeAfter)
    case setSide(ids: [UUID], side: Side)
    case applyRootSide(ids: [UUID], side: Side)
    case pasteAsChild(payload: [Node], parentId: UUID)
}
