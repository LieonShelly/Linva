import Testing
import Foundation
@testable import YMindApp

@Suite("CommandBus")
struct CommandBusTests {
    @Test func addChild_undo_redo() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        bus.execute(.addChild(parentId: model.document.root.id, text: "子"))
        #expect(model.document.root.children.count == 1)
        let childId = model.document.root.children[0].id
        bus.undo()
        #expect(model.document.root.children.isEmpty)
        bus.redo()
        #expect(model.document.root.children.count == 1)
        #expect(model.document.root.children[0].id == childId)
        #expect(model.document.root.children[0].text == "子")
    }

    @Test func delete_root_isNoOp() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        bus.execute(.delete(ids: [model.document.root.id]))
        #expect(model.document.root.children.isEmpty)
        #expect(!bus.canUndo)
    }

    @Test func clearHistory_onDemand() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        bus.execute(.addChild(parentId: model.document.root.id, text: "A"))
        bus.clearHistory()
        #expect(!bus.canUndo)
        #expect(!bus.canRedo)
    }

    @Test func deleteMany_undo_restoresSubtreesInOneStep() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "A", side: .left, at: nil)
        let b = model.insertChild(parentId: root, text: "B", side: .right, at: nil)
        bus.clearHistory()
        bus.execute(.delete(ids: [a, b]))
        #expect(model.document.root.children.isEmpty)
        bus.undo()
        #expect(Set(model.document.root.children.map(\.id)) == [a, b])
        #expect(Set(model.selectedIds) == [a, b])
    }

    @Test func delete_rootAndChild_skipsRoot_oneUndoRestoresChild() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "A", side: .left, at: nil)
        bus.clearHistory()
        bus.execute(.delete(ids: [root, a]))
        #expect(model.document.root.children.isEmpty)
        #expect(model.node(id: a) == nil)
        bus.undo()
        #expect(model.document.root.children.count == 1)
        #expect(model.document.root.children[0].id == a)
        #expect(Set(model.selectedIds) == [a])
    }

    @Test func delete_parentAndChild_onlyDeletesParent_oneUndoRestoresSubtree() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        let p = model.insertChild(parentId: root, text: "P", side: .right, at: nil)
        let c = model.insertChild(parentId: p, text: "C", side: nil, at: nil)
        bus.clearHistory()
        bus.execute(.delete(ids: [p, c]))
        #expect(model.node(id: p) == nil)
        #expect(model.node(id: c) == nil)
        bus.undo()
        #expect(model.node(id: p) != nil)
        #expect(model.node(id: c) != nil)
        #expect(model.node(id: p)?.children.count == 1)
        #expect(model.node(id: p)?.children[0].id == c)
        #expect(Set(model.selectedIds) == [p])
    }

    @Test func setCollapsed_oneUndo_restoresEachNodePreviousValue() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        model.insertChild(parentId: a, text: "A 子", side: nil, at: nil)
        let b = model.insertChild(parentId: root, text: "B", side: .left, at: nil)
        model.insertChild(parentId: b, text: "B 子", side: nil, at: nil)
        model.setCollapsed(id: a, to: true)
        bus.clearHistory()

        bus.execute(.setCollapsed(ids: [a, b], collapsed: true))
        #expect(model.node(id: a)?.collapsed == true)
        #expect(model.node(id: b)?.collapsed == true)

        bus.undo()
        #expect(model.node(id: a)?.collapsed == true)
        #expect(model.node(id: b)?.collapsed == false)

        bus.redo()
        #expect(model.node(id: b)?.collapsed == true)
    }

    @Test func setCollapsed_skipsLeaves_andNoOpWhenValueUnchanged() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        let leaf = model.insertChild(parentId: root, text: "叶", side: .right, at: nil)
        let branch = model.insertChild(parentId: root, text: "枝", side: .left, at: nil)
        model.insertChild(parentId: branch, text: "孙", side: nil, at: nil)
        bus.clearHistory()

        bus.execute(.setCollapsed(ids: [leaf], collapsed: true))
        #expect(!bus.canUndo)
        #expect(model.node(id: leaf)?.collapsed == false)

        bus.execute(.setCollapsed(ids: [branch], collapsed: false))
        #expect(!bus.canUndo)
    }

    @Test func collapseCommands_onChildlessNode_areNoOp() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let leaf = model.insertChild(parentId: model.document.root.id, text: "叶", side: .right, at: nil)
        bus.clearHistory()

        bus.execute(.toggleCollapse(id: leaf, side: nil))

        #expect(!bus.canUndo)
        #expect(model.node(id: leaf)?.collapsed == false)
    }

    @Test func toggleCollapse_collapsedChildless_expands() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        let leaf = model.insertChild(parentId: root, text: "叶", side: .right, at: nil)
        // 直接构造「已折叠但无子」状态（等价于文件中带 collapsed 的叶子）。
        model.setCollapsed(id: leaf, to: true)
        bus.clearHistory()

        bus.execute(.toggleCollapse(id: leaf, side: nil))

        #expect(bus.canUndo)
        #expect(model.node(id: leaf)?.collapsed == false)
        bus.undo()
        #expect(model.node(id: leaf)?.collapsed == true)
    }

    @Test func toggleCollapse_rootSide_collapsesOnlyThatSide_andUndoRestores() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        _ = model.insertChild(parentId: root, text: "L", side: .left, at: nil)
        _ = model.insertChild(parentId: root, text: "R", side: .right, at: nil)
        bus.clearHistory()

        bus.execute(.toggleCollapse(id: root, side: .left))

        #expect(bus.canUndo)
        #expect(model.document.root.collapsedLeft == true)
        #expect(model.document.root.collapsedRight == false)

        bus.undo()
        #expect(model.document.root.collapsedLeft == false)
        #expect(model.document.root.collapsedRight == false)

        bus.redo()
        #expect(model.document.root.collapsedLeft == true)
        #expect(model.document.root.collapsedRight == false)
    }

    @Test func moveToParent_undoRestoresPosition_andSelection() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        let b = model.insertChild(parentId: root, text: "B", side: .left, at: nil)
        bus.clearHistory()

        bus.execute(.moveToParent(ids: [a], parentId: b))
        #expect(model.node(id: b)?.children.map(\.id) == [a])
        #expect(Set(model.selectedIds) == [a])

        bus.undo()
        #expect(model.parentId(of: a) == root)
        #expect(Set(model.selectedIds) == [a])

        bus.redo()
        #expect(model.node(id: b)?.children.map(\.id) == [a])
    }

    @Test func pasteAsChild_undoRemovesCopies_redoReinsertsSameIds() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        let target = model.insertChild(parentId: root, text: "T", side: .left, at: nil)
        let src = model.node(id: a)!
        bus.clearHistory()

        bus.execute(.pasteAsChild(payload: [src], parentId: target))
        let pastedId = model.node(id: target)!.children[0].id
        #expect(model.node(id: target)?.children.count == 1)
        #expect(pastedId != a)
        #expect(Set(model.selectedIds) == [pastedId])

        bus.undo()
        #expect(model.node(id: target)?.children.isEmpty == true)
        #expect(model.node(id: pastedId) == nil)

        bus.redo()
        #expect(model.node(id: target)?.children.map(\.id) == [pastedId])
    }

    // R4：两兄弟 moveToParent 的 Undo 回归——移除时刻下标捕获 + 逆序恢复。
    @Test func moveToParent_twoSiblings_undoRestoresBothUnderRoot() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        let b = model.insertChild(parentId: root, text: "B", side: .left, at: nil)
        let x = model.insertChild(parentId: root, text: "X", side: nil, at: nil)
        bus.clearHistory()

        bus.execute(.moveToParent(ids: [a, b], parentId: x))
        let xChildren = model.node(id: x)?.children.map(\.id) ?? []
        #expect(xChildren.count == 2)
        #expect(Set(xChildren) == [a, b])
        #expect(Set(model.selectedIds) == [a, b])

        bus.undo()
        #expect(model.parentId(of: a) == root)
        #expect(model.parentId(of: b) == root)
        #expect(model.node(id: x)?.children.isEmpty == true)
        #expect(Set(model.document.root.children.map(\.id)) == [a, b, x])
        // A、B 恢复为兄弟（相对顺序不要求）：
        let rootChildIds = model.document.root.children.map(\.id)
        #expect(rootChildIds.filter { $0 == a || $0 == b }.count == 2)
    }

    @Test func insertSiblings_undoRestoresOriginalParentsAndOrder() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        let b = model.insertChild(parentId: root, text: "B", side: .left, at: nil)
        let g1 = model.insertChild(parentId: b, text: "G1", side: nil, at: nil)
        let g2 = model.insertChild(parentId: b, text: "G2", side: nil, at: nil)

        bus.execute(.insertSiblings(ids: [g1, g2], anchorId: a, position: .before))
        #expect(model.parentId(of: g1) == root)

        bus.undo()
        #expect(model.parentId(of: g1) == b)
        #expect(model.parentId(of: g2) == b)
        let bKids = model.node(id: b)!.children.map(\.id)
        #expect(bKids == [g1, g2])   // 原父/下标/顺序恢复

        bus.redo()
        #expect(model.parentId(of: g1) == root)
    }

    @Test func setSide_undoRestoresOldSide() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "A", side: .right, at: nil)

        bus.execute(.setSide(ids: [a], side: .left))
        #expect(model.node(id: a)?.side == .left)

        bus.undo()
        #expect(model.node(id: a)?.side == .right)

        bus.redo()
        #expect(model.node(id: a)?.side == .left)
    }

    @Test func applyRootSide_undoUnpromotes() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        let g = model.insertChild(parentId: a, text: "G", side: nil, at: nil)

        bus.execute(.applyRootSide(ids: [g], side: .left))
        #expect(model.parentId(of: g) == root)
        #expect(model.node(id: g)?.side == .left)

        bus.undo()
        #expect(model.parentId(of: g) == a)
        #expect(model.node(id: g)?.side == nil)

        bus.redo()
        #expect(model.parentId(of: g) == root)
    }

    // 终审 M3-1：同父移位 [A,B,C] → insertSiblings(A, anchor: C, .after) → [B,C,A]；Undo 还原。
    @Test func insertSiblings_sameParent_shiftAfter_orderAndUndo() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        let b = model.insertChild(parentId: root, text: "B", side: .left, at: nil)
        let c = model.insertChild(parentId: root, text: "C", side: nil, at: nil)
        bus.clearHistory()

        bus.execute(.insertSiblings(ids: [a], anchorId: c, position: .after))
        #expect(model.document.root.children.map(\.id) == [b, c, a])

        bus.undo()
        #expect(model.document.root.children.map(\.id) == [a, b, c])

        bus.redo()
        #expect(model.document.root.children.map(\.id) == [b, c, a])
    }

    // 终审 M3-2：跨父 .after —— 把 A 的子节点移到另一分支锚点后，验证顺序 + Undo。
    @Test func insertSiblings_after_crossParent_restoresOrderAndUndo() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        let g = model.insertChild(parentId: a, text: "G", side: nil, at: nil)
        let x = model.insertChild(parentId: root, text: "X", side: .left, at: nil)
        bus.clearHistory()

        bus.execute(.insertSiblings(ids: [g], anchorId: x, position: .after))
        #expect(model.parentId(of: g) == root)
        #expect(model.document.root.children.map(\.id) == [a, x, g])
        #expect(model.node(id: a)?.children.isEmpty == true)

        bus.undo()
        #expect(model.parentId(of: g) == a)
        #expect(model.node(id: a)?.children.map(\.id) == [g])
        #expect(model.document.root.children.map(\.id) == [a, x])

        bus.redo()
        #expect(model.parentId(of: g) == root)
        #expect(model.document.root.children.map(\.id) == [a, x, g])
    }

    // 终审 M3-3 / I1：被清空的折叠源父，前向强置展开，Undo 还原子节点并重新折叠。
    @Test func insertSiblings_undo_recollapsesEmptiedCollapsedSourceParent() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        let b = model.insertChild(parentId: root, text: "B", side: .left, at: nil)
        let c1 = model.insertChild(parentId: b, text: "C1", side: nil, at: nil)
        let c2 = model.insertChild(parentId: b, text: "C2", side: nil, at: nil)
        model.setCollapsed(id: b, to: true)
        bus.clearHistory()

        bus.execute(.insertSiblings(ids: [c1, c2], anchorId: a, position: .after))
        // 前向清空 B → B 被 removeWithoutChangingSelection 强置展开。
        #expect(model.node(id: b)?.children.isEmpty == true)
        #expect(model.node(id: b)?.collapsed == false)
        #expect(Set(model.document.root.children.map(\.id)) == [a, b, c1, c2])

        bus.undo()
        // Undo 还原子节点并重折叠 B。
        #expect(model.node(id: b)?.children.map(\.id) == [c1, c2])
        #expect(model.node(id: b)?.collapsed == true)

        bus.redo()
        #expect(model.node(id: b)?.children.isEmpty == true)
        #expect(model.node(id: b)?.collapsed == false)
    }

    @Test func setFill_undoRedo_restoresEachOldValue() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "A", side: .left, at: nil)
        let b = model.insertChild(parentId: root, text: "B", side: .right, at: nil)
        model.document.root.fill = .sage
        _ = model.mutate(id: a) { $0.fill = .sky }
        bus.clearHistory()
        bus.execute(.setFill(ids: [root, a, b], fill: .lilac))
        #expect(model.node(id: root)?.fill == .lilac)
        #expect(model.node(id: a)?.fill == .lilac)
        #expect(model.node(id: b)?.fill == .lilac)
        bus.undo()
        #expect(model.node(id: root)?.fill == .sage)
        #expect(model.node(id: a)?.fill == .sky)
        #expect(model.node(id: b)?.fill == nil)
        bus.redo()
        #expect(model.node(id: root)?.fill == .lilac)
        #expect(model.node(id: a)?.fill == .lilac)
        #expect(model.node(id: b)?.fill == .lilac)
    }

    @Test func setFill_noChange_isNoOp() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        bus.execute(.setFill(ids: [root], fill: nil))
        #expect(!bus.canUndo)
        model.document.root.fill = .sage
        bus.execute(.setFill(ids: [root], fill: .sage))
        #expect(!bus.canUndo)
    }

    @Test func setLayout_undoRedo_roundTrips() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        #expect(model.document.layout == .radial)

        bus.execute(.setLayout(kind: .logic))
        #expect(model.document.layout == .logic)

        bus.undo()
        #expect(model.document.layout == .radial)

        bus.redo()
        #expect(model.document.layout == .logic)
    }

    @Test func setLayout_sameKind_isNoOp() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        bus.execute(.setLayout(kind: .radial))
        #expect(!bus.canUndo)
        #expect(model.document.layout == .radial)
    }
}

@Suite("块命令")
struct BlockCommandTests {
    @Test func setBlocks_undoRedo() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        let old = model.document.root.blocks
        let new = [ContentBlock(id: UUID(), kind: .text("新文本"))]
        bus.execute(.setBlocks(id: root, old: old, new: new))
        #expect(model.node(id: root)?.blocks == new)
        bus.undo()
        #expect(model.node(id: root)?.blocks == old)
        bus.redo()
        #expect(model.node(id: root)?.blocks == new)
    }

    @Test func appendImageBlock_undoRemoves_redoReinsertsSameId() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        let px = ImagePixelSize(width: 10, height: 10)!
        bus.execute(.appendImageBlock(id: root, image: Data([0x01]), pixelSize: px))
        let blockId = model.node(id: root)!.blocks[1].id
        #expect(model.node(id: root)?.blocks.count == 2)
        bus.undo()
        #expect(model.node(id: root)?.blocks.count == 1)
        bus.redo()
        #expect(model.node(id: root)?.blocks[1].id == blockId)
    }

    @Test func replaceImageBlock_undoRestoresOld() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        let px = ImagePixelSize(width: 10, height: 10)!
        bus.execute(.appendImageBlock(id: root, image: Data([0x01]), pixelSize: px))
        let blockId = model.node(id: root)!.blocks[1].id
        bus.execute(.replaceImageBlock(id: root, blockId: blockId, image: Data([0x02]), pixelSize: px))
        if case .image(let img) = model.node(id: root)!.blocks[1].kind {
            #expect(img.data == Data([0x02]))
        }
        bus.undo()
        if case .image(let img) = model.node(id: root)!.blocks[1].kind {
            #expect(img.data == Data([0x01]))
        }
        bus.redo()
        if case .image(let img) = model.node(id: root)!.blocks[1].kind {
            #expect(img.data == Data([0x02]))
        }
    }

    @Test func removeImageBlock_undoRestoresBlockAtSameIndex() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        let px = ImagePixelSize(width: 10, height: 10)!
        bus.execute(.appendImageBlock(id: root, image: Data([0x01]), pixelSize: px))
        let blockId = model.node(id: root)!.blocks[1].id
        bus.execute(.removeImageBlock(id: root, blockId: blockId))
        #expect(model.node(id: root)?.blocks.count == 1)
        bus.undo()
        #expect(model.node(id: root)?.blocks.count == 2)
        #expect(model.node(id: root)?.blocks[1].id == blockId)
        bus.redo()
        #expect(model.node(id: root)?.blocks.count == 1)
    }

    @Test func noOpSetBlocks_doesNotEnterUndoStack() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        let old = model.document.root.blocks
        bus.execute(.setBlocks(id: root, old: old, new: old))
        #expect(bus.canUndo == false)
    }

    // M1：guard 分支——old 过期（node.blocks 已被并发改动）→ 拒绝执行，且不覆盖现状。
    @Test func setBlocks_staleOld_doesNotOverwrite() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        let old = model.document.root.blocks
        let new = [ContentBlock(id: UUID(), kind: .text("新文本"))]
        let concurrent = [ContentBlock(id: UUID(), kind: .text("并发写入"))]
        model.mutate(id: root) { $0.blocks = concurrent }   // 模拟并发/过期：blocks 已与 old 不同

        bus.execute(.setBlocks(id: root, old: old, new: new))

        #expect(bus.canUndo == false)
        #expect(model.node(id: root)?.blocks == concurrent)  // 保持手动改后的值，未被 old 覆盖
    }

    // M1：guard 分支——replaceImageBlock 目标块不存在 → 返回 nil 不入栈。
    @Test func replaceImageBlock_missingBlock_noOp() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        let px = ImagePixelSize(width: 10, height: 10)!
        let before = model.document.root.blocks

        bus.execute(.replaceImageBlock(id: root, blockId: UUID(), image: Data([0x02]), pixelSize: px))

        #expect(bus.canUndo == false)
        #expect(model.node(id: root)?.blocks == before)
    }

    // M1：guard 分支——removeImageBlock 目标块不存在 → 返回 nil 不入栈。
    @Test func removeImageBlock_missingBlock_noOp() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        let before = model.document.root.blocks

        bus.execute(.removeImageBlock(id: root, blockId: UUID()))

        #expect(bus.canUndo == false)
        #expect(model.node(id: root)?.blocks == before)
    }
}
