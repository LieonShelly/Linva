import CoreGraphics
import Testing
@testable import YMindApp

@Suite("放置意图解析")
struct DropIntentTests {
    private func makeModel() -> MindMapModel {
        let model = MindMapModel.makeNew()
        let root = model.document.root.id
        _ = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        _ = model.insertChild(parentId: root, text: "B", side: .left, at: nil)
        return model
    }

    /// 屏幕点 = 世界点（camera 恒等）：scale=1、translation=0。
    private let camera = Camera()

    @Test func beforeZone_top28Percent() throws {
        let model = makeModel()
        let snapshot = RadialLayout.layout(document: model.document, measure: TextMeasure())
        let a = try #require(model.node(id: model.document.root.children[0].id))
        let frame = try #require(snapshot.frames[a.id])
        let y = frame.rect.minY + frame.rect.height * 0.1  // 上 28% 内
        let point = CGPoint(x: frame.rect.midX, y: y)
        // moving 用另一兄弟（与锚点 a 无祖先关系）
        let moving = [model.document.root.children[1].id]

        let intent = resolveDropIntent(
            screenPoint: point, movingIds: Set(moving),
            snapshot: snapshot, camera: camera, model: model
        )
        #expect(intent == .before(targetId: a.id))
    }

    @Test func childZone_middle() throws {
        let model = makeModel()
        let snapshot = RadialLayout.layout(document: model.document, measure: TextMeasure())
        let a = try #require(model.node(id: model.document.root.children[0].id))
        let frame = try #require(snapshot.frames[a.id])
        let point = CGPoint(x: frame.rect.midX, y: frame.rect.midY)
        let moving = [model.document.root.children[1].id]

        #expect(resolveDropIntent(screenPoint: point, movingIds: Set(moving), snapshot: snapshot, camera: camera, model: model) == .child(targetId: a.id))
    }

    @Test func afterZone_bottom28Percent() throws {
        let model = makeModel()
        let snapshot = RadialLayout.layout(document: model.document, measure: TextMeasure())
        let a = try #require(model.node(id: model.document.root.children[0].id))
        let frame = try #require(snapshot.frames[a.id])
        let y = frame.rect.maxY - frame.rect.height * 0.1
        let point = CGPoint(x: frame.rect.midX, y: y)
        let moving = [model.document.root.children[1].id]

        #expect(resolveDropIntent(screenPoint: point, movingIds: Set(moving), snapshot: snapshot, camera: camera, model: model) == .after(targetId: a.id))
    }

    @Test func insertSibling_rejectsAnchorAndAncestor() throws {
        let model = makeModel()
        let root = model.document.root.id
        let a = model.document.root.children[0].id
        let g = model.insertChild(parentId: a, text: "G", side: nil, at: nil)

        // 锚点在被搬集
        #expect(!canInsertSibling([a], anchorId: a, model: model))
        // 被搬集含锚点祖先
        #expect(!canInsertSibling([a], anchorId: g, model: model))
        // 合法：搬无关兄弟到 a 前
        let b = model.document.root.children[1].id
        #expect(canInsertSibling([b], anchorId: a, model: model))
    }

    @Test func root_sideZonesAndChild() throws {
        let model = makeModel()
        let snapshot = RadialLayout.layout(document: model.document, measure: TextMeasure())
        let rootFrame = try #require(snapshot.frames[model.document.root.id])
        let moving = [model.document.root.children[0].id]

        let leftPoint = CGPoint(x: rootFrame.rect.minX + rootFrame.rect.width * 0.1, y: rootFrame.rect.midY)
        #expect(resolveDropIntent(screenPoint: leftPoint, movingIds: Set(moving), snapshot: snapshot, camera: camera, model: model) == .sideLeft(targetId: model.document.root.id, viaEmpty: false))

        let midPoint = CGPoint(x: rootFrame.rect.midX, y: rootFrame.rect.midY)
        #expect(resolveDropIntent(screenPoint: midPoint, movingIds: Set(moving), snapshot: snapshot, camera: camera, model: model) == .child(targetId: model.document.root.id))
    }

    @Test func emptySide_onlyAllRootChildren_andSplitsByWorldX() throws {
        let model = makeModel()
        let snapshot = RadialLayout.layout(document: model.document, measure: TextMeasure())
        let moving = [model.document.root.children[0].id]

        // 空白 + 世界 x<0 → left
        let leftEmpty = CGPoint(x: -200, y: -200)
        #expect(resolveDropIntent(screenPoint: leftEmpty, movingIds: Set(moving), snapshot: snapshot, camera: camera, model: model) == .sideLeft(targetId: model.document.root.id, viaEmpty: true))
        let rightEmpty = CGPoint(x: 200, y: -200)
        #expect(resolveDropIntent(screenPoint: rightEmpty, movingIds: Set(moving), snapshot: snapshot, camera: camera, model: model) == .sideRight(targetId: model.document.root.id, viaEmpty: true))

        // 深层节点拖空白 → 无改侧意图
        let a = model.document.root.children[0].id
        let g = model.insertChild(parentId: a, text: "G", side: nil, at: nil)
        #expect(resolveDropIntent(screenPoint: rightEmpty, movingIds: Set([g]), snapshot: snapshot, camera: camera, model: model) == nil)
    }
}
