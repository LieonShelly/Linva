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
            guard let node = model.node(id: id), !node.children.isEmpty else { return nil }
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
        }
    }
}
