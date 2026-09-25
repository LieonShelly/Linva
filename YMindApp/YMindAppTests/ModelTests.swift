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
        model.selectOnly(child)
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

    @Test func topLevelDeletableIds_skipsDescendantsWhenAncestorSelected() {
        let model = MindMapModel.makeNew()
        let root = model.document.root.id
        let p = model.insertChild(parentId: root, text: "P", side: .right, at: nil)
        let c = model.insertChild(parentId: p, text: "C", side: nil, at: nil)
        let ids = model.topLevelDeletableIds(from: [p, c, root])
        #expect(ids == [p])
    }

    @Test func removeLastChild_resetsCollapsed() {
        let model = MindMapModel.makeNew()
        let root = model.document.root.id
        let branch = model.insertChild(parentId: root, text: "枝", side: .right, at: nil)
        let child = model.insertChild(parentId: branch, text: "子", side: nil, at: nil)
        model.setCollapsed(id: branch, to: true)

        model.remove(id: child)

        #expect(model.node(id: branch)?.children.isEmpty == true)
        #expect(model.node(id: branch)?.collapsed == false)
    }

    @Test func removeMany_followsDeterministicTotalOrder() {
        func node(_ id: UUID, text: String) -> Node {
            Node(id: id, text: text)
        }
        let p1 = UUID(uuidString: "11111111-0000-0000-0000-000000000001")!
        let p2 = UUID(uuidString: "22222222-0000-0000-0000-000000000002")!
        let a = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
        let m = UUID(uuidString: "00000000-0000-0000-0000-000000000008")!
        let z = UUID(uuidString: "00000000-0000-0000-0000-000000000009")!
        var doc = MindMapDocument.blank()
        doc.root.children = [
            Node(id: p1, text: "P1", children: (0..<10).map { i in
                let id: UUID
                switch i {
                case 5: id = a
                case 9: id = z
                default:
                    id = UUID(uuidString: String(
                        format: "00000000-0000-0000-0000-000000000f%02d", i
                    ))!
                }
                return node(id, text: "n\(i)")
            }),
            Node(id: p2, text: "P2", children: [node(m, text: "M")]),
        ]
        let model = MindMapModel(document: doc)

        let removed = model.removeMany(ids: [a, m, z])

        // 父按 uuid 升序，同父按下标降序；旧谓词会在 A<M<Z 时成环。
        #expect(removed.map(\.node.id) == [z, a, m])
        #expect(model.node(id: a) == nil)
        #expect(model.node(id: m) == nil)
        #expect(model.node(id: z) == nil)
    }
}
