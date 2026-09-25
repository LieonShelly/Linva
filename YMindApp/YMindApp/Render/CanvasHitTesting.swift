import CoreGraphics
import Foundation

enum CanvasHit: Equatable {
    case branchToggle(nodeId: UUID)
    case node(UUID)
    case empty
}

/// 分叉控件的胶囊外框（世界坐标）。宽度随「−N」位数增长；中心恒在「节点边缘 + 间隙」处
/// （规格 §4.1），因此宽度封顶到该间隙，避免药丸与节点矩形相接。
func branchToggleWorldRect(_ toggle: BranchToggle) -> CGRect {
    let digits = toggle.collapsed ? String(toggle.hiddenCount).count : 0
    let radius = LayoutConstants.branchToggleVisualRadius
    let halfWidth = min(radius + CGFloat(digits) * 2, LayoutConstants.branchToggleGap)
    return CGRect(
        x: toggle.center.x - halfWidth,
        y: toggle.center.y - radius,
        width: halfWidth * 2,
        height: radius * 2
    )
}

/// 命中区 = 视觉外框外扩 (视觉半径 → 命中半径) 的余量，横向再封顶到节点间隙。
/// 由此同时成立：命中区覆盖整颗药丸（含「−N」加宽后的两端），且不越界到节点矩形内。
func branchToggleHitContains(_ toggle: BranchToggle, worldPoint: CGPoint) -> Bool {
    let pill = branchToggleWorldRect(toggle)
    let margin = LayoutConstants.branchToggleHitRadius - LayoutConstants.branchToggleVisualRadius
    let halfWidth = min(pill.width / 2 + margin, LayoutConstants.branchToggleGap)
    return abs(worldPoint.x - toggle.center.x) <= halfWidth
        && abs(worldPoint.y - toggle.center.y) <= LayoutConstants.branchToggleHitRadius
}

/// 命中顺序：分叉控件 → 节点 → 空白。世界坐标判定，控件命中半径略大于视觉圆。
func hitTestCanvas(
    screenPoint: CGPoint,
    snapshot: LayoutSnapshot,
    camera: Camera
) -> CanvasHit {
    let world = camera.screenToWorld(screenPoint)
    if let toggle = snapshot.branchToggles.first(where: {
        branchToggleHitContains($0, worldPoint: world)
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

/// 位移超过拖拽阈值（与框选阈值一致的 4pt）才进入搬枝拖拽。
func hasExceededDragThreshold(from origin: CGPoint, to current: CGPoint) -> Bool {
    !isClickLike(marqueeRect(from: origin, to: current))
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
