import Foundation

final class CommandBus {
    private let model: MindMapModel
    private var undoStack: [Entry] = []
    private var redoStack: [Entry] = []
    var onChange: (() -> Void)?

    private struct Entry {
        let undo: () -> Void
        let redo: () -> Void
    }

    init(model: MindMapModel) { self.model = model }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    func execute(_ command: MindMapCommand) {
        guard let entry = applyForward(command) else { return }
        undoStack.append(entry)
        redoStack.removeAll()
        onChange?()
    }

    func undo() {
        guard let entry = undoStack.popLast() else { return }
        entry.undo()
        redoStack.append(entry)
        onChange?()
    }

    func redo() {
        guard let entry = redoStack.popLast() else { return }
        entry.redo()
        undoStack.append(entry)
        onChange?()
    }

    private func entryForInsertedNode(id: UUID) -> Entry? {
        guard let snapshot = model.node(id: id),
              let parentId = model.parentId(of: id),
              let index = model.indexInParent(of: id) else { return nil }
        return Entry(
            undo: { _ = self.model.remove(id: id) },
            redo: {
                self.model.restoreChild(parentId: parentId, index: index, node: snapshot)
                self.model.selectOnly(snapshot.id)
            }
        )
    }

    private func applyDelete(ids: [UUID]) -> Entry? {
        let tops = model.topLevelDeletableIds(from: Set(ids))
        guard !tops.isEmpty else { return nil }
        let removed = model.removeMany(ids: tops)
        guard !removed.isEmpty else { return nil }
        let restoredSelection = Set(removed.map(\.node.id))
        return Entry(
            undo: {
                for item in removed.reversed() {
                    self.model.restoreChild(
                        parentId: item.parentId,
                        index: item.index,
                        node: item.node
                    )
                }
                self.model.replaceSelection(
                    restoredSelection,
                    anchorId: restoredSelection.min { $0.uuidString < $1.uuidString }
                )
            },
            redo: { _ = self.model.removeMany(ids: tops) }
        )
    }

    private func applyForward(_ command: MindMapCommand) -> Entry? {
        switch command {
        case let .addChild(parentId, text):
            let newId = model.insertChild(parentId: parentId, text: text, side: nil, at: nil)
            return entryForInsertedNode(id: newId)

        case let .addSibling(selectedId, text):
            guard let newId = model.insertSibling(of: selectedId, text: text) else { return nil }
            return entryForInsertedNode(id: newId)

        case let .delete(ids):
            return applyDelete(ids: ids)

        case let .setText(id, old, new):
            model.setText(id: id, new)
            return Entry(
                undo: { self.model.setText(id: id, old) },
                redo: { self.model.setText(id: id, new) }
            )

        case let .toggleCollapse(id):
            // 折叠方向要求有子节点；展开方向不受限（修复「已折叠但无子」的叶子，见 F1）。
            guard let node = model.node(id: id),
                  !node.children.isEmpty || node.collapsed else {
                return nil
            }
            model.toggleCollapse(id: id)
            return Entry(
                undo: { self.model.toggleCollapse(id: id) },
                redo: { self.model.toggleCollapse(id: id) }
            )

        case let .setCollapsed(ids, collapsed):
            // 只作用于有子节点的节点；目标值无变化时视为 no-op，不入栈。
            var seen = Set<UUID>()
            let targets = ids
                .filter { seen.insert($0).inserted }
                .filter { model.node(id: $0)?.children.isEmpty == false }
                .sorted { $0.uuidString < $1.uuidString }
            guard targets.contains(where: { model.node(id: $0)?.collapsed != collapsed }) else {
                return nil
            }
            let previousValues = targets.map { id in
                (id: id, collapsed: model.node(id: id)?.collapsed ?? false)
            }
            for id in targets {
                model.setCollapsed(id: id, to: collapsed)
            }
            return Entry(
                undo: {
                    for item in previousValues {
                        self.model.setCollapsed(id: item.id, to: item.collapsed)
                    }
                },
                redo: {
                    for id in targets {
                        self.model.setCollapsed(id: id, to: collapsed)
                    }
                }
            )

        case let .moveToParent(ids, parentId):
            let priorTargetCollapsed = model.node(id: parentId)?.collapsed
            let priorSourceCollapsed = sourceParentCollapsed(for: ids)
            let records = model.reparent(ids: ids, to: parentId)
            guard !records.isEmpty else { return nil }
            let movedIds = Set(records.map(\.node.id))
            let anchor = movedIds.min { $0.uuidString < $1.uuidString }
            model.replaceSelection(movedIds, anchorId: anchor)
            return Entry(
                undo: {
                    // 先从目标父移除被搬节点，再按原父/原下标恢复，避免节点同时存在于新旧两处。
                    for r in records.sorted(by: { $0.index < $1.index }) {
                        _ = self.model.removeWithoutSelection(id: r.node.id)
                        self.model.restoreChild(parentId: r.parentId, index: r.index, node: r.node)
                    }
                    if let priorTargetCollapsed {
                        self.model.setCollapsed(id: parentId, to: priorTargetCollapsed)
                    }
                    // 源父可能因清空被 removeWithoutChangingSelection 强置展开，Undo 时还原折叠态。
                    for (id, collapsed) in priorSourceCollapsed {
                        self.model.setCollapsed(id: id, to: collapsed)
                    }
                    self.model.replaceSelection(movedIds, anchorId: anchor)
                },
                redo: {
                    _ = self.model.reparent(ids: ids, to: parentId)
                    self.model.replaceSelection(movedIds, anchorId: anchor)
                }
            )

        case let .insertSiblings(ids, anchorId, position):
            // 每个原始源父的折叠态须在执行前捕获；同父移动时锚点父即源父，一并覆盖。
            let priorSourceCollapsed = sourceParentCollapsed(for: ids)
            let records = model.insertSiblings(ids: ids, anchorId: anchorId, position: position)
            guard !records.isEmpty else { return nil }
            let movedIds = Set(records.map(\.node.id))
            let anchor = movedIds.min { $0.uuidString < $1.uuidString }
            model.replaceSelection(movedIds, anchorId: anchor)
            return Entry(
                undo: {
                    for r in records.sorted(by: { $0.index < $1.index }) {
                        _ = self.model.removeWithoutSelection(id: r.node.id)
                        self.model.restoreChild(parentId: r.parentId, index: r.index, node: r.node)
                    }
                    // 源父可能因清空被 removeWithoutChangingSelection 强置展开，Undo 时还原折叠态。
                    for (id, collapsed) in priorSourceCollapsed {
                        self.model.setCollapsed(id: id, to: collapsed)
                    }
                    self.model.replaceSelection(movedIds, anchorId: anchor)
                },
                redo: {
                    _ = self.model.insertSiblings(ids: ids, anchorId: anchorId, position: position)
                    self.model.replaceSelection(movedIds, anchorId: anchor)
                }
            )

        case let .setSide(ids, side):
            let changes = model.setSide(ids: ids, side: side)
            guard !changes.isEmpty else { return nil }
            return Entry(
                undo: {
                    for c in changes {
                        _ = self.model.mutate(id: c.id) { $0.side = c.oldSide }
                    }
                },
                redo: {
                    _ = self.model.setSide(ids: ids, side: side)
                }
            )

        case let .applyRootSide(ids, side):
            // 提升源父的折叠态须在执行前捕获；被提升清空的父会被 removeWithoutChangingSelection 强置展开。
            let priorSourceCollapsed = sourceParentCollapsed(for: ids)
            let change = model.applyRootSide(ids: ids, side: side)
            guard !change.sideChanges.isEmpty || !change.promotions.isEmpty else { return nil }
            return Entry(
                undo: {
                    for p in change.promotions.sorted(by: { $0.index < $1.index }) {
                        _ = self.model.removeWithoutSelection(id: p.node.id)
                        self.model.restoreChild(parentId: p.parentId, index: p.index, node: p.node)
                    }
                    for (id, collapsed) in priorSourceCollapsed {
                        self.model.setCollapsed(id: id, to: collapsed)
                    }
                    for c in change.sideChanges {
                        _ = self.model.mutate(id: c.id) { $0.side = c.oldSide }
                    }
                },
                redo: {
                    _ = self.model.applyRootSide(ids: ids, side: side)
                }
            )

        case let .setFill(ids, fill):
            let changes = model.setFill(ids: ids, fill: fill)
            guard !changes.isEmpty else { return nil }
            return Entry(
                undo: {
                    for c in changes {
                        _ = self.model.mutate(id: c.id) { $0.fill = c.oldFill }
                    }
                },
                redo: {
                    _ = self.model.setFill(ids: ids, fill: fill)
                }
            )

        case let .pasteAsChild(payload, parentId):
            let priorSelection = model.selectedIds
            let priorAnchor = model.selectionAnchorId
            let priorCollapsed = model.node(id: parentId)?.collapsed
            var inserted: [Node] = []
            for node in payload {
                let copy = model.duplicate(node)
                model.attachChild(copy, to: parentId)
                inserted.append(copy)
            }
            guard !inserted.isEmpty else { return nil }
            let insertedIds = Set(inserted.map(\.id))
            let anchor = insertedIds.min { $0.uuidString < $1.uuidString }
            if model.node(id: parentId)?.collapsed == true {
                model.setCollapsed(id: parentId, to: false)
            }
            model.replaceSelection(insertedIds, anchorId: anchor)
            return Entry(
                undo: {
                    for n in inserted {
                        _ = self.model.removeWithoutSelection(id: n.id)
                    }
                    if let priorCollapsed {
                        self.model.setCollapsed(id: parentId, to: priorCollapsed)
                    }
                    self.model.replaceSelection(priorSelection, anchorId: priorAnchor)
                },
                redo: {
                    for n in inserted {
                        self.model.attachChild(n, to: parentId)
                    }
                    if self.model.node(id: parentId)?.collapsed == true {
                        self.model.setCollapsed(id: parentId, to: false)
                    }
                    self.model.replaceSelection(insertedIds, anchorId: anchor)
                }
            )
        }
    }

    /// 各被搬节点原始父的折叠态（须在搬移执行前捕获；被清空的源父会在移除时被强置展开）。
    private func sourceParentCollapsed(for ids: [UUID]) -> [UUID: Bool] {
        var result: [UUID: Bool] = [:]
        for id in ids {
            guard let parentId = model.parentId(of: id),
                  let collapsed = model.node(id: parentId)?.collapsed,
                  result[parentId] == nil else { continue }
            result[parentId] = collapsed
        }
        return result
    }
}
