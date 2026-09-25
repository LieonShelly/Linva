import Foundation

final class MindMapModel {
    var document: MindMapDocument
    var selectedIds: Set<UUID> = []
    var selectionAnchorId: UUID?

    var primarySelectedId: UUID? {
        if let selectionAnchorId, selectedIds.contains(selectionAnchorId) {
            return selectionAnchorId
        }
        return selectedIds.min { $0.uuidString < $1.uuidString }
    }

    /// Temporary bridge until Session migrates in Task 2.
    var selectedId: UUID? {
        get { primarySelectedId }
        set { selectOnly(newValue) }
    }

    init(document: MindMapDocument, selectedId: UUID? = nil) {
        self.document = document
        let initial = selectedId ?? document.root.id
        selectedIds = [initial]
        selectionAnchorId = initial
    }

    static func makeNew() -> MindMapModel {
        let doc = MindMapDocument.blank()
        return MindMapModel(document: doc, selectedId: doc.root.id)
    }

    func selectOnly(_ id: UUID?) {
        guard let id else {
            selectedIds = []
            selectionAnchorId = nil
            return
        }
        guard node(id: id) != nil else { return }
        selectedIds = [id]
        selectionAnchorId = id
    }

    /// 兼容旧调用点：等价于 selectOnly
    func select(_ id: UUID?) { selectOnly(id) }

    func clearSelection() { selectOnly(nil) }

    func toggleInSelection(_ id: UUID) {
        guard node(id: id) != nil else { return }
        if selectedIds.contains(id) {
            selectedIds.remove(id)
            if selectionAnchorId == id {
                selectionAnchorId = primarySelectedId
            }
        } else {
            selectedIds.insert(id)
            selectionAnchorId = id
        }
    }

    func selectSiblingRange(to id: UUID) {
        guard node(id: id) != nil else { return }
        guard let anchor = selectionAnchorId,
              let anchorParent = parentId(of: anchor),
              let targetParent = parentId(of: id),
              anchorParent == targetParent,
              let parent = node(id: anchorParent) else {
            selectOnly(id)
            return
        }
        let ids = parent.children.map(\.id)
        guard let i0 = ids.firstIndex(of: anchor),
              let i1 = ids.firstIndex(of: id) else {
            selectOnly(id)
            return
        }
        let lo = min(i0, i1)
        let hi = max(i0, i1)
        selectedIds = Set(ids[lo...hi])
    }

    func replaceSelection(_ ids: Set<UUID>, anchorId: UUID?) {
        selectedIds = Set(ids.filter { node(id: $0) != nil })
        if let anchorId, selectedIds.contains(anchorId) {
            selectionAnchorId = anchorId
        } else {
            selectionAnchorId = primarySelectedId
        }
    }

    func node(id: UUID) -> Node? {
        Self.find(id: id, in: document.root)
    }

    func parent(of id: UUID) -> (parent: Node, index: Int)? {
        guard let path = pathTo(id), let parentId = path.parentId else { return nil }
        guard let parent = node(id: parentId) else { return nil }
        return (parent, path.index)
    }

    func parentId(of id: UUID) -> UUID? { pathTo(id)?.parentId }
    func indexInParent(of id: UUID) -> Int? { pathTo(id)?.index }

    @discardableResult
    func insertChild(parentId: UUID, text: String, side: Side?, at index: Int?) -> UUID {
        let newId = UUID()
        var assignedSide = side
        if parentId == document.root.id, assignedSide == nil {
            assignedSide = nextSide()
        }
        if parentId != document.root.id {
            assignedSide = nil
        }
        let child = Node(id: newId, text: text, side: assignedSide)
        _ = mutate(id: parentId) { parent in
            let i = index ?? parent.children.count
            parent.children.insert(child, at: min(i, parent.children.count))
        }
        selectOnly(newId)
        return newId
    }

    @discardableResult
    func insertSibling(of id: UUID, text: String) -> UUID? {
        guard id != document.root.id,
              var path = pathTo(id),
              let parentId = path.parentId else { return nil }
        let side: Side? = parentId == document.root.id
            ? (node(id: id)?.side)
            : nil
        return insertChild(parentId: parentId, text: text, side: side, at: path.index + 1)
    }

    @discardableResult
    func remove(id: UUID) -> (parentId: UUID, index: Int, node: Node)? {
        guard id != document.root.id, let path = pathTo(id), let parentId = path.parentId else {
            return nil
        }
        var removed: Node?
        _ = mutate(id: parentId) { parent in
            removed = parent.children.remove(at: path.index)
        }
        guard let removed else { return nil }
        selectOnly(parentId)
        return (parentId, path.index, removed)
    }

    func setText(id: UUID, _ text: String) {
        _ = mutate(id: id) { $0.text = text }
    }

    func toggleCollapse(id: UUID) {
        _ = mutate(id: id) { $0.collapsed.toggle() }
    }

    func restoreChild(parentId: UUID, index: Int, node: Node) {
        _ = mutate(id: parentId) { parent in
            parent.children.insert(node, at: min(index, parent.children.count))
        }
    }

    // MARK: - Private tree helpers

    private func nextSide() -> Side {
        let left = document.root.children.filter { $0.side == .left }.count
        let right = document.root.children.filter { $0.side != .left }.count
        return left <= right ? .left : .right
    }

    private static func find(id: UUID, in node: Node) -> Node? {
        if node.id == id { return node }
        for c in node.children {
            if let f = find(id: id, in: c) { return f }
        }
        return nil
    }

    private struct Path { var parentId: UUID?; var index: Int }

    private func pathTo(_ id: UUID) -> Path? {
        if document.root.id == id { return Path(parentId: nil, index: 0) }
        return pathTo(id, parent: document.root)
    }

    private func pathTo(_ id: UUID, parent: Node) -> Path? {
        for (i, c) in parent.children.enumerated() {
            if c.id == id { return Path(parentId: parent.id, index: i) }
            if let p = pathTo(id, parent: c) { return p }
        }
        return nil
    }

    @discardableResult
    private func mutate(id: UUID, _ body: (inout Node) -> Void) -> Bool {
        var root = document.root
        let ok = Self.mutate(&root, id: id, body)
        if ok { document.root = root }
        return ok
    }

    private static func mutate(_ node: inout Node, id: UUID, _ body: (inout Node) -> Void) -> Bool {
        if node.id == id {
            body(&node)
            return true
        }
        for i in node.children.indices {
            if mutate(&node.children[i], id: id, body) { return true }
        }
        return false
    }
}
