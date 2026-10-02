import Foundation
import Testing
@testable import YMindApp

@Suite("EditingController")
struct EditingControllerTests {
    private func frames(for model: MindMapModel) -> [UUID: NodeFrame] {
        RadialLayout.layout(document: model.document, measure: TextMeasure()).frames
    }

    /// begin → commit 提交聚拢后的 blocks，editingId 回落。
    @Test func begin_commit_updatesBlocksAndClearsEditing() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let controller = EditingController(model: model, commandBus: bus)
        let root = model.document.root.id

        #expect(controller.begin(id: root, currentDraft: "", snapshotFrames: frames(for: model)))
        controller.commit(draftText: "新标题")

        #expect(controller.editingId == nil)
        #expect(model.document.root.text == "新标题")
    }

    /// 无 frame 的节点 begin 失败（编辑静默不启动）。
    @Test func begin_withoutFrame_fails() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let controller = EditingController(model: model, commandBus: bus)
        let ghost = UUID()

        #expect(controller.begin(id: ghost, currentDraft: "", snapshotFrames: [:]) == false)
        #expect(controller.editingId == nil)
    }

    /// 切换编辑目标时先提交旧节点。
    @Test func begin_switchNode_commitsPrevious() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let controller = EditingController(model: model, commandBus: bus)
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        let f = frames(for: model)

        #expect(controller.begin(id: root, currentDraft: "", snapshotFrames: f))
        #expect(controller.begin(id: a, currentDraft: "根的新文", snapshotFrames: f))

        #expect(model.document.root.text == "根的新文")  // 旧节点（根）先被提交
        #expect(controller.editingId == a)
    }

    /// cancel 丢弃草稿，树不变。
    @Test func cancel_doesNotMutateTree() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let controller = EditingController(model: model, commandBus: bus)
        let root = model.document.root.id

        controller.begin(id: root, currentDraft: "", snapshotFrames: frames(for: model))
        controller.cancel()

        #expect(controller.editingId == nil)
        #expect(model.document.root.text == "中心主题")
    }
}
