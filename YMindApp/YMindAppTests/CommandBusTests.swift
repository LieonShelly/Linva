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
        bus.execute(.delete(id: model.document.root.id))
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
}
