import Testing
import Foundation
@testable import LinvaApp

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

    @Test func movableTopLevel_excludesRoot_andDedupsAncestors() {
        let model = MindMapModel.makeNew()
        let root = model.document.root.id
        let p = model.insertChild(parentId: root, text: "P", side: .right, at: nil)
        let c = model.insertChild(parentId: p, text: "C", side: nil, at: nil)
        let ids = model.movableTopLevel(ids: [root, p, c])
        #expect(ids == [p])
    }

    @Test func duplicate_preservesStructure_withNewIds() {
        let model = MindMapModel.makeNew()
        let root = model.document.root.id
        let p = model.insertChild(parentId: root, text: "P", side: .right, at: nil)
        let c = model.insertChild(parentId: p, text: "C", side: nil, at: nil)
        let src = model.node(id: p)!

        let copy = model.duplicate(src)

        #expect(copy.text == "P")
        #expect(copy.children.count == 1)
        #expect(copy.children[0].text == "C")
        #expect(copy.id != src.id)
        #expect(copy.children[0].id != c)
        #expect(copy.children[0].id != copy.id)
    }

    /// P1-A：duplicate 重生成块 id——副本图片块不得与原节点共享块 id
    /// （纹理缓存/导出 assets/<blockId>.png 按块 id 寻址，共享即碰撞）。
    @Test func duplicate_regeneratesBlockIds() {
        let model = MindMapModel.makeNew()
        let root = model.document.root.id
        let p = model.insertChild(parentId: root, text: "P", side: .right, at: nil)
        let px = ImagePixelSize(width: 10, height: 10)!
        let imgBlockId = model.appendImageBlock(id: p, image: Data([0x01]), pixelSize: px)
        let src = model.node(id: p)!

        let copy = model.duplicate(src)

        let srcBlocks = src.blocks
        let copyBlocks = copy.blocks
        #expect(srcBlocks.count == copyBlocks.count)                       // 块数保持
        #expect(srcBlocks.map(\.kind) == copyBlocks.map(\.kind))           // 内容与顺序保持
        #expect(Set(srcBlocks.map(\.id)).isDisjoint(with: copyBlocks.map(\.id)))  // 块 id 全部重生成
        #expect(copyBlocks.contains(where: { $0.id == imgBlockId }) == false)     // 原图片块 id 不出现在副本
    }

    @Test func reparent_movesUnderTarget_andExpands() {
        let model = MindMapModel.makeNew()
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        let b = model.insertChild(parentId: root, text: "B", side: .left, at: nil)
        model.setCollapsed(id: b, to: true)

        let records = model.reparent(ids: [a], to: b)

        #expect(records.count == 1)
        #expect(model.node(id: b)?.children.map(\.id) == [a])
        #expect(model.node(id: b)?.collapsed == false)
    }

    @Test func reparent_toOwnDescendant_isNoOp() {
        let model = MindMapModel.makeNew()
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        let g = model.insertChild(parentId: a, text: "G", side: nil, at: nil)

        let records = model.reparent(ids: [a], to: g)

        #expect(records.isEmpty)
        #expect(model.parentId(of: a) == root)
    }

    @Test func reparent_toRoot_assignsSide() {
        let model = MindMapModel.makeNew()
        let root = model.document.root.id
        let p = model.insertChild(parentId: root, text: "P", side: .right, at: nil)
        let c = model.insertChild(parentId: p, text: "C", side: nil, at: nil)

        let records = model.reparent(ids: [c], to: root)

        #expect(records.count == 1)
        #expect(model.node(id: c)?.side != nil)
    }

    @Test func isValidDropTarget_rejectsSelfAndDescendant() {
        let model = MindMapModel.makeNew()
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        let g = model.insertChild(parentId: a, text: "G", side: nil, at: nil)

        #expect(model.isValidDropTarget(root, movingIds: [a]))          // 根可作目标
        #expect(!model.isValidDropTarget(a, movingIds: [a]))            // 自身
        #expect(!model.isValidDropTarget(g, movingIds: [a]))            // 后代
        #expect(model.isValidDropTarget(g, movingIds: [a, g]) == false) // 目标在被搬集内
    }

    @Test func insertSiblings_crossParent_before_preservesOrder_andInheritsSide() {
        let model = MindMapModel.makeNew()
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        let b = model.insertChild(parentId: root, text: "B", side: .left, at: nil)
        let g1 = model.insertChild(parentId: b, text: "G1", side: nil, at: nil)
        let g2 = model.insertChild(parentId: b, text: "G2", side: nil, at: nil)

        // 把 b 下的 G1、G2 插到 a 之前（跨父，同父 b 下标 G1=0,G2=1 → 保持相对序）
        let records = model.insertSiblings(ids: [g1, g2], anchorId: a, position: .before)

        #expect(records.count == 2)
        #expect(model.parentId(of: g1) == root)
        #expect(model.parentId(of: g2) == root)
        // a 现在 root.children 中下标 1；g1,g2 在 a 前（下标 0,1）
        let kids = model.node(id: root)!.children.map(\.id)
        #expect(kids.firstIndex(of: g1)! < kids.firstIndex(of: a)!)
        #expect(kids.firstIndex(of: g2)! < kids.firstIndex(of: a)!)
        #expect(kids.firstIndex(of: g1)! < kids.firstIndex(of: g2)!)
    }

    @Test func insertSiblings_underRoot_inheritsAnchorSide() {
        let model = MindMapModel.makeNew()
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        let b = model.insertChild(parentId: root, text: "B", side: .left, at: nil)
        let g = model.insertChild(parentId: b, text: "G", side: nil, at: nil)

        _ = model.insertSiblings(ids: [g], anchorId: a, position: .before)

        // g 提升为中心直接子，继承锚点 a 的 side=.right
        #expect(model.node(id: g)?.side == .right)
    }

    @Test func setSide_onlyRootDirectChildren() {
        let model = MindMapModel.makeNew()
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        let g = model.insertChild(parentId: a, text: "G", side: nil, at: nil)

        let changes = model.setSide(ids: [a, g], side: .left)

        // 仅一级枝 a 被改；g 忽略
        #expect(changes.count == 1)
        #expect(changes[0].id == a)
        #expect(changes[0].oldSide == .right)
        #expect(model.node(id: a)?.side == .left)
        #expect(model.node(id: g)?.side == nil)
    }

    @Test func applyRootSide_promotesDeeperAndChangesExisting() {
        let model = MindMapModel.makeNew()
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        let g = model.insertChild(parentId: a, text: "G", side: nil, at: nil)

        let change = model.applyRootSide(ids: [g], side: .left)

        // g 提升为一级 + left
        #expect(model.parentId(of: g) == root)
        #expect(model.node(id: g)?.side == .left)
        #expect(change.promotions.count == 1)
        #expect(change.promotions[0].parentId == a)

        // a 已是中心直接子：只改侧
        let change2 = model.applyRootSide(ids: [a], side: .left)
        #expect(change2.sideChanges.count == 1)
        #expect(model.node(id: a)?.side == .left)
    }

    @Test func searchMatches_dfsOrder_caseInsensitive_includesCollapsed() {
        let model = MindMapModel.makeNew()
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "技术方案 tech", side: .right, at: nil)
        let g = model.insertChild(parentId: a, text: "命中测试", side: nil, at: nil)
        model.setCollapsed(id: a, to: true)

        let ids = model.searchMatches(query: "命中")

        #expect(ids == [g])           // 折叠子树内仍匹配
        #expect(model.searchMatches(query: "技术").contains(a))
        #expect(model.searchMatches(query: "TECH").contains(a))  // 大小写不敏感
        #expect(model.searchMatches(query: "").isEmpty)
        #expect(model.searchMatches(query: "不存在xyz").isEmpty)
    }
}
