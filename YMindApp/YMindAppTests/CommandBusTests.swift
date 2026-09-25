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

    @Test func setText_undo() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let id = model.document.root.id
        bus.execute(.setText(id: id, old: "中心主题", new: "会议"))
        #expect(model.document.root.text == "会议")
        bus.undo()
        #expect(model.document.root.text == "中心主题")
        bus.redo()
        #expect(model.document.root.text == "会议")
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

        bus.execute(.toggleCollapse(id: leaf))

        #expect(!bus.canUndo)
        #expect(model.node(id: leaf)?.collapsed == false)
    }
}
