import Foundation

struct ReparentRecord: Equatable {
    let parentId: UUID
    let index: Int
    let node: Node
}

enum BeforeAfter { case before, after }

struct RootSideChange {
    let sideChanges: [(id: UUID, oldSide: Side?)]
    let promotions: [ReparentRecord]
}

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

    init(document: MindMapDocument) {
        self.document = document
        selectedIds = [document.root.id]
        selectionAnchorId = document.root.id
    }

    static func makeNew() -> MindMapModel {
        MindMapModel(document: .blank())
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
        guard let removed = removeWithoutChangingSelection(id: id) else { return nil }
        selectOnly(removed.parentId)
        return removed
    }

    /// Non-root ids whose ancestors are not also in `ids` (delete those; skip nested duplicates).
    func topLevelDeletableIds(from ids: Set<UUID>) -> [UUID] {
        let rootId = document.root.id
        return ids.filter { id in
            guard id != rootId, node(id: id) != nil else { return false }
            var parent = parentId(of: id)
            while let p = parent {
                if p != rootId, ids.contains(p) { return false }
                parent = parentId(of: p)
            }
            return true
        }
    }

    /// 可搬顶层：排除中心主题，祖先已在集内则不再单列（语义与批量删除一致）。
    func movableTopLevel(ids: Set<UUID>) -> [UUID] {
        topLevelDeletableIds(from: ids)
    }

    /// 深拷贝子树并递归换新 UUID（Node 为值类型，结构天然深拷贝，只需换 id）。
    /// 块 id 一并重生成：剪贴板复制粘贴的副本不得与原节点共享块 id
    /// （imagePayloads/纹理缓存/导出 assets/<blockId>.png 按块 id 寻址，共享即碰撞）。
    func duplicate(_ node: Node) -> Node {
        var copy = node
        copy.id = UUID()
        copy.blocks = node.blocks.map { ContentBlock(id: UUID(), kind: $0.kind) }
        copy.children = node.children.map { duplicate($0) }
        return copy
    }

    /// Removes nodes without thrashing selection mid-loop; then selects first surviving parent or clears.
    @discardableResult
    func removeMany(ids: [UUID]) -> [(parentId: UUID, index: Int, node: Node)] {
        let ordered = ids.compactMap { id -> (UUID, Int, UUID)? in
            guard let p = parentId(of: id), let i = indexInParent(of: id) else { return nil }
            return (p, i, id)
        }
        // 严格全序：先按父 id 排序，同父再按下标降序，避免跨父分支时比较谓词成环。
        .sorted { lhs, rhs in
            if lhs.0 != rhs.0 { return lhs.0.uuidString < rhs.0.uuidString }
            return lhs.1 > rhs.1
        }

        var removed: [(parentId: UUID, index: Int, node: Node)] = []
        var parentCandidates: [UUID] = []
        for (_, _, id) in ordered {
            if let r = removeWithoutChangingSelection(id: id) {
                removed.append(r)
                parentCandidates.append(r.parentId)
            }
        }
        if let keep = parentCandidates.first(where: { node(id: $0) != nil }) {
            selectOnly(keep)
        } else {
            clearSelection()
        }
        return removed
    }

    /// 整块序列替换（编辑提交）。前置校验：old 须与当前一致（防串改覆盖），且 old != new（无变化不入栈）。
    @discardableResult
    func setBlocks(id: UUID, old: [ContentBlock], new: [ContentBlock]) -> Bool {
        guard let node = node(id: id), node.blocks == old, old != new else { return false }
        _ = mutate(id: id) { $0.blocks = new }
        return true
    }

    /// 末尾追加图片块；返回新块 id（redo 用同 id 重插，经 blockId 参数）。
    @discardableResult
    func appendImageBlock(
        id: UUID,
        image: Data,
        pixelSize: ImagePixelSize,
        blockId: UUID? = nil
    ) -> UUID {
        let block = ContentBlock(id: blockId ?? UUID(), kind: .image(.init(data: image, pixelSize: pixelSize)))
        _ = mutate(id: id) { $0.blocks.append(block) }
        return block.id
    }

    /// 替换指定图片块数据（块 id 不变）；返回旧块供 Undo；无该块返回 nil。
    @discardableResult
    func replaceImageBlock(id: UUID, blockId: UUID, image: Data, pixelSize: ImagePixelSize) -> ContentBlock? {
        guard let node = node(id: id),
              let index = node.blocks.firstIndex(where: { $0.id == blockId }),
              case .image = node.blocks[index].kind else {
            return nil
        }
        let old = node.blocks[index]
        _ = mutate(id: id) {
            $0.blocks[index] = ContentBlock(
                id: blockId,
                kind: .image(.init(data: image, pixelSize: pixelSize))
            )
        }
        return old
    }

    /// 删除图片块；返回被删块与下标供 Undo 按原位置恢复；无该块/非图片块返回 nil。
    @discardableResult
    func removeImageBlock(id: UUID, blockId: UUID) -> (block: ContentBlock, index: Int)? {
        guard let node = node(id: id),
              let index = node.blocks.firstIndex(where: { $0.id == blockId }),
              case .image = node.blocks[index].kind else {
            return nil
        }
        let block = node.blocks[index]
        _ = mutate(id: id) { $0.blocks.remove(at: index) }
        return (block, index)
    }

    /// 单一折叠态（非根用 collapsed；根用左右两侧同时折叠的聚合态）。
    func isCollapsed(_ id: UUID) -> Bool {
        if id == document.root.id {
            return document.root.collapsedLeft && document.root.collapsedRight
        }
        return node(id: id)?.collapsed ?? false
    }

    /// 切换折叠。根节点支持按侧独立折叠（`side` 指定只折该侧；nil 折两侧——逻辑图/整体语义）；
    /// 非根节点忽略 side，折其自身 collapsed。
    func toggleCollapse(id: UUID, side: Side? = nil) {
        if id == document.root.id {
            if let side {
                if side == .left {
                    document.root.collapsedLeft.toggle()
                } else {
                    document.root.collapsedRight.toggle()
                }
            } else {
                document.root.collapsedLeft.toggle()
                document.root.collapsedRight.toggle()
            }
            return
        }
        _ = mutate(id: id) { $0.collapsed.toggle() }
    }

    func setCollapsed(id: UUID, to collapsed: Bool) {
        if id == document.root.id {
            document.root.collapsedLeft = collapsed
            document.root.collapsedRight = collapsed
            return
        }
        _ = mutate(id: id) { $0.collapsed = collapsed }
    }

    /// 对选中集每个节点写同一 fill（含根）；返回被改节点旧值供 Undo。不改选中。
    @discardableResult
    func setFill(ids: [UUID], fill: NodeFill?) -> [(id: UUID, oldFill: NodeFill?)] {
        var changes: [(id: UUID, oldFill: NodeFill?)] = []
        var seen = Set<UUID>()
        for id in ids where seen.insert(id).inserted {
            guard let node = node(id: id), node.fill != fill else { continue }
            changes.append((id, node.fill))
            _ = mutate(id: id) { $0.fill = fill }
        }
        return changes
    }

    /// 设置文档布局（文档属性，与选中无关）；返回旧值供 Undo；无变化返回 nil（no-op 不入栈）。
    @discardableResult
    func setLayout(_ kind: LayoutKind) -> LayoutKind? {
        guard document.layout != kind else { return nil }
        let old = document.layout
        document.layout = kind
        return old
    }

    /// 设置文档连线样式（文档属性，与选中无关）；返回旧值供 Undo；无变化返回 nil（no-op 不入栈）。
    @discardableResult
    func setEdgeStyle(_ kind: EdgeStyle) -> EdgeStyle? {
        guard document.edgeStyle != kind else { return nil }
        let old = document.edgeStyle
        document.edgeStyle = kind
        return old
    }

    func restoreChild(parentId: UUID, index: Int, node: Node) {
        _ = mutate(id: parentId) { parent in
            parent.children.insert(node, at: min(index, parent.children.count))
        }
    }

    /// 把可搬顶层整体搬到 targetId 下（末尾）；守卫 targetId 不为被搬节点自身/后代。
    /// 目标为中心主题时按 v1「侧」均衡规则分配 left/right；成功后 target.collapsed = false。
    @discardableResult
    func reparent(ids: [UUID], to targetId: UUID) -> [ReparentRecord] {
        let moving = movableTopLevel(ids: Set(ids))
        guard !moving.isEmpty,
              node(id: targetId) != nil,
              !moving.contains(targetId),
              !moving.contains(where: { isDescendant(targetId, of: $0) }) else {
            return []
        }

        var records: [ReparentRecord] = []
        for id in moving {
            guard let path = pathTo(id),
                  let oldParent = path.parentId,
                  let node = node(id: id) else { continue }
            _ = removeWithoutChangingSelection(id: id)
            records.append(ReparentRecord(parentId: oldParent, index: path.index, node: node))
            attachChild(node, to: targetId)
        }
        _ = mutate(id: targetId) { $0.collapsed = false }
        // 目标为根时折叠态由左右侧独立字段承载：清两侧（reparent 落根即展开）。
        if targetId == document.root.id {
            document.root.collapsedLeft = false
            document.root.collapsedRight = false
        }
        return records
    }

    /// 可搬顶层卸下后按锚点前后插入为连续块（FR-R2）；跨父；新父为中心时 side 继承锚点（否则 nextSide）。
    @discardableResult
    func insertSiblings(ids: [UUID], anchorId: UUID, position: BeforeAfter) -> [ReparentRecord] {
        let tops = movableTopLevel(ids: Set(ids))
        guard !tops.isEmpty,
              anchorId != document.root.id,
              let anchorParentId = parentId(of: anchorId),
              !tops.contains(anchorId),
              !tops.contains(where: { isDescendant(anchorId, of: $0) }) else {
            return []
        }

        // 严格全序 detach：先按父 id 排序，同父再按下标降序（与 removeMany 一致）。
        let ordered = tops
            .compactMap { id -> (UUID, Int, UUID)? in
                guard let p = parentId(of: id), let i = indexInParent(of: id) else { return nil }
                return (p, i, id)
            }
            .sorted { lhs, rhs in
                if lhs.0 != rhs.0 { return lhs.0.uuidString < rhs.0.uuidString }
                return lhs.1 > rhs.1
            }

        var records: [ReparentRecord] = []
        for (parentId, index, id) in ordered {
            guard let node = node(id: id) else { continue }
            _ = removeWithoutChangingSelection(id: id)
            records.append(ReparentRecord(parentId: parentId, index: index, node: node))
        }
        // 倒序 detach 后反转为原相对序
        records.reverse()

        // anchor 可能已因跨父被搬走（锚点在被搬集被守卫排除，故仍在原父）。
        guard let anchorIndex = indexInParent(of: anchorId) else {
            // 理论上不可达；保守回滚
            for r in records { restoreChild(parentId: r.parentId, index: r.index, node: r.node) }
            return []
        }
        var insertAt = position == .before ? anchorIndex : anchorIndex + 1
        let anchorNode = node(id: anchorId)
        for r in records {
            var n = r.node
            if anchorParentId == document.root.id {
                n.side = anchorNode?.side ?? nextSide()
            } else {
                n.side = nil
            }
            _ = mutate(id: anchorParentId) { parent in
                parent.children.insert(n, at: min(insertAt, parent.children.count))
            }
            insertAt += 1
        }
        return records
    }

    /// 仅作用中心直接子，设 side；返回被改节点快照供 Undo。
    @discardableResult
    func setSide(ids: [UUID], side: Side) -> [(id: UUID, oldSide: Side?)] {
        var changes: [(id: UUID, oldSide: Side?)] = []
        for id in ids where parentId(of: id) == document.root.id {
            guard let node = node(id: id), node.side != side else { continue }
            changes.append((id, node.side))
            _ = mutate(id: id) { $0.side = side }
        }
        return changes
    }

    /// 中心直接子只改 side；更深提升为一级并设 side；返回撤销记录。
    @discardableResult
    func applyRootSide(ids: [UUID], side: Side) -> RootSideChange {
        let tops = movableTopLevel(ids: Set(ids))
        var sideChanges: [(id: UUID, oldSide: Side?)] = []
        var promotions: [ReparentRecord] = []
        for id in tops {
            if parentId(of: id) == document.root.id {
                guard let node = node(id: id), node.side != side else { continue }
                sideChanges.append((id, node.side))
                _ = mutate(id: id) { $0.side = side }
            } else {
                guard let p = parentId(of: id),
                      let index = indexInParent(of: id),
                      let node = node(id: id) else { continue }
                _ = removeWithoutChangingSelection(id: id)
                promotions.append(ReparentRecord(parentId: p, index: index, node: node))
                _ = mutate(id: document.root.id) { root in
                    var n = node
                    n.side = side
                    root.children.append(n)
                }
            }
        }
        return RootSideChange(sideChanges: sideChanges, promotions: promotions)
    }

    /// DFS 先序、大小写不敏感子串包含；含折叠子树；空查询返回空。
    func searchMatches(query: String) -> [UUID] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var ids: [UUID] = []
        func walk(_ node: Node) {
            if node.text.lowercased().contains(q) { ids.append(node.id) }
            for child in node.children { walk(child) }
        }
        walk(document.root)
        return ids
    }

    /// 把既有节点追加为 parentId 的子；目标为中心主题时自动分侧。不改选中。
    func attachChild(_ node: Node, to parentId: UUID) {
        _ = mutate(id: parentId) { parent in
            var n = node
            if parentId == document.root.id { n.side = nextSide() }
            parent.children.append(n)
        }
    }

    /// 移除但不改选中（供粘贴 Undo 等）。
    func removeWithoutSelection(id: UUID) -> (parentId: UUID, index: Int, node: Node)? {
        removeWithoutChangingSelection(id: id)
    }

    /// nodeId 是否在 ancestorId 的子树中（不含 ancestorId 自身）。
    func isDescendant(_ nodeId: UUID, of ancestorId: UUID) -> Bool {
        guard nodeId != ancestorId,
              let ancestor = node(id: ancestorId) else { return false }
        return Self.find(id: nodeId, in: ancestor) != nil
    }

    /// 拖放/粘贴目标合法性：存在、不在被搬集内、不是任一被搬节点的后代。
    func isValidDropTarget(_ target: UUID, movingIds: Set<UUID>) -> Bool {
        guard node(id: target) != nil, !movingIds.contains(target) else { return false }
        return !movingIds.contains { isDescendant(target, of: $0) }
    }

    // MARK: - Private tree helpers

    @discardableResult
    private func removeWithoutChangingSelection(id: UUID) -> (parentId: UUID, index: Int, node: Node)? {
        guard id != document.root.id, let path = pathTo(id), let parentId = path.parentId else {
            return nil
        }
        var removed: Node?
        _ = mutate(id: parentId) { parent in
            removed = parent.children.remove(at: path.index)
            if parent.children.isEmpty {
                // 维持「collapsed ⇒ 有子节点」不变量。
                parent.collapsed = false
                if parent.id == document.root.id {
                    // 根折叠态由左右侧独立字段承载：清两侧。
                    parent.collapsedLeft = false
                    parent.collapsedRight = false
                }
            }
        }
        guard let removed else { return nil }
        return (parentId, path.index, removed)
    }

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
    func mutate(id: UUID, _ body: (inout Node) -> Void) -> Bool {
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
