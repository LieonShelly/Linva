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
        #expect(model.selectedIds == [model.document.root.id])
        #expect(model.selectionAnchorId == model.document.root.id)
        #expect(model.primarySelectedId == model.document.root.id)
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
        #expect(model.selectedIds == [rootId])
        #expect(model.document.root.children.isEmpty)
    }

    @Test func remove_root_returnsNil() {
        let model = MindMapModel.makeNew()
        #expect(model.remove(id: model.document.root.id) == nil)
    }

    @Test func selectNil_clearsSelection() {
        let model = MindMapModel.makeNew()
        model.selectOnly(nil)
        #expect(model.selectedIds.isEmpty)
        #expect(model.selectionAnchorId == nil)
        #expect(model.primarySelectedId == nil)
    }

    @Test func toggleInSelection_addsAndRemoves() {
        let model = MindMapModel.makeNew()
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "A", side: .left, at: nil)
        let b = model.insertChild(parentId: root, text: "B", side: .right, at: nil)
        model.selectOnly(a)
        model.toggleInSelection(b)
        #expect(model.selectedIds == [a, b])
        #expect(model.selectionAnchorId == b)
        model.toggleInSelection(a)
        #expect(model.selectedIds == [b])
    }

    @Test func selectSiblingRange_sameParent_selectsInclusiveRange() {
        let model = MindMapModel.makeNew()
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        let b = model.insertChild(parentId: root, text: "B", side: .right, at: nil)
        let c = model.insertChild(parentId: root, text: "C", side: .right, at: nil)
        model.selectOnly(a)
        model.selectSiblingRange(to: c)
        #expect(model.selectedIds == [a, b, c])
    }

    @Test func selectSiblingRange_differentParent_selectsOnlyTarget() {
        let model = MindMapModel.makeNew()
        let root = model.document.root.id
        let parent = model.insertChild(parentId: root, text: "P", side: .right, at: nil)
        let child = model.insertChild(parentId: parent, text: "C", side: nil, at: nil)
        let other = model.insertChild(parentId: root, text: "O", side: .left, at: nil)
        model.selectOnly(child)
        model.selectSiblingRange(to: other)
        #expect(model.selectedIds == [other])
        #expect(model.selectionAnchorId == other)
    }
}
