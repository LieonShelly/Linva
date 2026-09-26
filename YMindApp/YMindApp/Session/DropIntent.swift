import CoreGraphics
import Foundation

/// 拖拽放置意图：统一「成子 / 插前 / 插后 / 改侧」四类。
enum DropIntent: Equatable {
    case child(targetId: UUID)
    case before(targetId: UUID)
    case after(targetId: UUID)
    case sideLeft(targetId: UUID, viaEmpty: Bool)
    case sideRight(targetId: UUID, viaEmpty: Bool)
}

/// 非中心节点上/下边缘占比 → 同级插入带（对齐原型 DROP_EDGE_RATIO=0.28，上下对称）。
let dropEdgeRatio: CGFloat = 0.28

/// 插到锚点前/后为同级：锚点须有父；被搬集非空；锚点不在被搬集；被搬集不含锚点祖先。
func canInsertSibling(_ movingIds: [UUID], anchorId: UUID, model: MindMapModel) -> Bool {
    let tops = model.movableTopLevel(ids: Set(movingIds))
    guard !tops.isEmpty,
          let anchorParentId = model.parentId(of: anchorId) else { return false }
    guard !tops.contains(anchorId) else { return false }
    for id in tops where model.isDescendant(anchorId, of: id) {
        return false
    }
    _ = anchorParentId
    return true
}

/// 节点命中则按目标分区，否则空白过中线改侧。
func resolveDropIntent(
    screenPoint: CGPoint,
    movingIds: Set<UUID>,
    snapshot: LayoutSnapshot,
    camera: Camera,
    model: MindMapModel
) -> DropIntent? {
    let world = camera.screenToWorld(screenPoint)
    // 节点命中：取面积最小的可见节点（与 hitTestNode 一致）
    guard let target = snapshot.frames.values
        .filter({ $0.rect.contains(world) })
        .min(by: { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }) else {
        return resolveEmptySideIntent(screenPoint: screenPoint, movingIds: movingIds, camera: camera, model: model)
    }

    if target.isRoot {
        let u = (world.x - target.rect.minX) / max(target.rect.width, 1)
        if u < 1.0 / 3.0 { return .sideLeft(targetId: target.id, viaEmpty: false) }
        if u > 2.0 / 3.0 { return .sideRight(targetId: target.id, viaEmpty: false) }
        return model.isValidDropTarget(target.id, movingIds: movingIds)
            ? .child(targetId: target.id)
            : nil
    }

    let t = (world.y - target.rect.minY) / max(target.rect.height, 1)
    let tops = model.movableTopLevel(ids: movingIds)
    if t < dropEdgeRatio {
        return canInsertSibling(tops, anchorId: target.id, model: model)
            ? .before(targetId: target.id) : nil
    }
    if t > 1 - dropEdgeRatio {
        return canInsertSibling(tops, anchorId: target.id, model: model)
            ? .after(targetId: target.id) : nil
    }
    return model.isValidDropTarget(target.id, movingIds: movingIds)
        ? .child(targetId: target.id)
        : nil
}

/// 空白过中线改侧：仅当被拖可搬顶层全部已是中心直接子；世界 x<0 → left，≥0 → right。
func resolveEmptySideIntent(
    screenPoint: CGPoint,
    movingIds: Set<UUID>,
    camera: Camera,
    model: MindMapModel
) -> DropIntent? {
    let tops = model.movableTopLevel(ids: movingIds)
    guard !tops.isEmpty else { return nil }
    for id in tops {
        guard let parentId = model.parentId(of: id), parentId == model.document.root.id else {
            return nil
        }
    }
    let world = camera.screenToWorld(screenPoint)
    return world.x < 0
        ? .sideLeft(targetId: model.document.root.id, viaEmpty: true)
        : .sideRight(targetId: model.document.root.id, viaEmpty: true)
}
