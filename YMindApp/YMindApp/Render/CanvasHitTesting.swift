import CoreGraphics
import Foundation

enum CanvasHit: Equatable {
    case branchToggle(nodeId: UUID)
    case node(UUID)
    case empty
}

/// 命中顺序：分叉控件 → 节点 → 空白。世界坐标判定，控件命中半径略大于视觉圆。
func hitTestCanvas(
    screenPoint: CGPoint,
    snapshot: LayoutSnapshot,
    camera: Camera
) -> CanvasHit {
    let world = camera.screenToWorld(screenPoint)
    let hitRadius = LayoutConstants.branchToggleHitRadius
    let hitRadiusSquared = hitRadius * hitRadius
    if let toggle = snapshot.branchToggles.first(where: {
        let dx = world.x - $0.center.x
        let dy = world.y - $0.center.y
        return dx * dx + dy * dy <= hitRadiusSquared
    }) {
        return .branchToggle(nodeId: toggle.nodeId)
    }
    if let id = hitTestNode(screenPoint: screenPoint, snapshot: snapshot, camera: camera) {
        return .node(id)
    }
    return .empty
}

func hitTestNode(
    screenPoint: CGPoint,
    snapshot: LayoutSnapshot,
    camera: Camera
) -> UUID? {
    let worldPoint = camera.screenToWorld(screenPoint)
    return snapshot.frames.values
        .filter { $0.rect.contains(worldPoint) }
        .min {
            $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height
        }?
        .id
}

/// 与框选世界矩形相交的可见节点（折叠隐藏的节点不在 `frames` 中，天然不可选）。
func marqueeIntersectingIds(
    worldRect: CGRect,
    snapshot: LayoutSnapshot
) -> Set<UUID> {
    Set(
        snapshot.frames.values
            .filter { $0.rect.intersects(worldRect) }
            .map(\.id)
    )
}

/// 位移小于该阈值（视图点）视为「点空白」而非框选，对齐原型。
let marqueeClickThreshold: CGFloat = 4

/// 归一化框选矩形（视图坐标，左上/右下任意方向拖动皆可）。
func marqueeRect(from start: CGPoint, to end: CGPoint) -> CGRect {
    CGRect(
        x: min(start.x, end.x),
        y: min(start.y, end.y),
        width: abs(end.x - start.x),
        height: abs(end.y - start.y)
    )
}

func isClickLike(_ rect: CGRect) -> Bool {
    rect.width < marqueeClickThreshold && rect.height < marqueeClickThreshold
}

/// 视图矩形 → 世界矩形。`Camera.scale > 0`，min/max 顺序在变换后保持。
func worldRect(fromScreenRect rect: CGRect, camera: Camera) -> CGRect {
    let origin = camera.screenToWorld(rect.origin)
    let corner = camera.screenToWorld(CGPoint(x: rect.maxX, y: rect.maxY))
    return CGRect(
        x: origin.x,
        y: origin.y,
        width: corner.x - origin.x,
        height: corner.y - origin.y
    )
}
