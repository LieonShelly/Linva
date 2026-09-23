import Testing
import Foundation
@testable import YMindApp

@Suite("MindMapModel")
struct ModelTests {
    @Test func makeNew_hasSingleRootSelected() {
        let model = MindMapModel.makeNew()
        #expect(model.document.version == MindMapDocument.currentVersion)
        #expect(model.document.root.text == "中心主题")
        #expect(model.document.root.children.isEmpty)
        #expect(model.selectedId == model.document.root.id)
    }

    @Test func insertChild_onRoot_assignsBalancedSide() {
        let model = MindMapModel.makeNew()
        let rootId = model.document.root.id
        let a = model.insertChild(parentId: rootId, text: "A", side: nil, at: nil)
        let b = model.insertChild(parentId: rootId, text: "B", side: nil, at: nil)
        let c = model.insertChild(parentId: rootId, text: "C", side: nil, at: nil)
        let sides = model.document.root.children.map(\.side)
        #expect(sides == [.left, .right, .left] || sides == [.left, .right, .right])
        // 均衡：left 与 right 数量差 ≤ 1
        let left = sides.filter { $0 == .left }.count
        let right = sides.filter { $0 == .right }.count
        #expect(abs(left - right) <= 1)
        #expect(Set([a, b, c]).count == 3)
    }

    @Test func remove_selectsParent() {
        let model = MindMapModel.makeNew()
        let rootId = model.document.root.id
        let child = model.insertChild(parentId: rootId, text: "X", side: .right, at: nil)
        model.select(child)
        let removed = model.remove(id: child)
        #expect(removed != nil)
        #expect(model.selectedId == rootId)
        #expect(model.document.root.children.isEmpty)
    }

    @Test func remove_root_returnsNil() {
        let model = MindMapModel.makeNew()
        #expect(model.remove(id: model.document.root.id) == nil)
    }
}
