import Foundation

enum MindMapCommand: Equatable {
    case addChild(parentId: UUID, text: String)
    case addSibling(selectedId: UUID, text: String)
    case delete(ids: [UUID])
    case setBlocks(id: UUID, old: [ContentBlock], new: [ContentBlock])
    case appendImageBlock(id: UUID, image: Data, pixelSize: ImagePixelSize)
    case replaceImageBlock(id: UUID, blockId: UUID, image: Data, pixelSize: ImagePixelSize)
    case removeImageBlock(id: UUID, blockId: UUID)
    case toggleCollapse(id: UUID, side: Side?)
    case setCollapsed(ids: [UUID], collapsed: Bool)
    case moveToParent(ids: [UUID], parentId: UUID)
    case insertSiblings(ids: [UUID], anchorId: UUID, position: BeforeAfter)
    case setSide(ids: [UUID], side: Side)
    case applyRootSide(ids: [UUID], side: Side)
    case pasteAsChild(payload: [Node], parentId: UUID)
    case setFill(ids: [UUID], fill: NodeFill?)
    case setLayout(kind: LayoutKind)
    case setEdgeStyle(kind: EdgeStyle)
}
