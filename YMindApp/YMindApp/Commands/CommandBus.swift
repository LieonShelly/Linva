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
                self.model.select(snapshot.id)
            }
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

        case let .delete(id):
            guard let removed = model.remove(id: id) else { return nil }
            return Entry(
                undo: {
                    self.model.restoreChild(
                        parentId: removed.parentId,
                        index: removed.index,
                        node: removed.node
                    )
                    self.model.select(removed.node.id)
                },
                redo: { _ = self.model.remove(id: id) }
            )

        case let .setText(id, old, new):
            model.setText(id: id, new)
            return Entry(
                undo: { self.model.setText(id: id, old) },
                redo: { self.model.setText(id: id, new) }
            )

        case let .toggleCollapse(id):
            model.toggleCollapse(id: id)
            return Entry(
                undo: { self.model.toggleCollapse(id: id) },
                redo: { self.model.toggleCollapse(id: id) }
            )
        }
    }
}
