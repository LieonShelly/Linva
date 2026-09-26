# YMind 同级排序 + 搜索定位 + 手动改侧（合并）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有 YMindApp 上一次交付三份增量：同级排序（分区命中插前/后）、搜索定位（⌘F 浮层 + 整树匹配 + 展开/居中/高亮）、手动改侧（命令 + 拖拽落中心半/空白过中线），行为对齐三份 PRD 与原型。

**Architecture:** 沿用 v1 分层。核心是 `DropIntent` 枚举统一「成子 / 插前 / 插后 / 改侧」四类放置意图，替换现有 `dropTarget: UUID?`；`resolveDropIntent` 纯函数对齐原型分区。`MindMapModel` 增 `insertSiblings` / `setSide` / `applyRootSide` / `searchMatches`；`MindMapCommand` 增 `insertSiblings` / `setSide` / `applyRootSide`（各为命令栈一步）；`DocumentSession` 增搜索态与 `revealSearchMatch`；`MetalRenderer` 画插入线 / 根镶边 / 中线引导 / 搜索高亮；壳层加搜索浮层、改侧工具条、⌘F/⌘G/⌘←/⌘→ 快捷键。

**Tech Stack:** Swift、SwiftUI、AppKit（NSEvent 修饰键）、MetalKit、Swift Testing；工程 `YMindApp/`（`PBXFileSystemSynchronizedRootGroup`）。

**Spec:** `docs/superpowers/specs/2026-09-26-ymind-reorder-search-side-design.md`

## Global Constraints

- 平台：macOS（工程 `MACOSX_DEPLOYMENT_TARGET = 26.4`）
- 选中 / 相机 / **搜索态 / 放置意图** 均不入 `.ymind`；文件格式 version 不变
- 排序分区常量 `DROP_EDGE_RATIO = 0.28`（对齐原型，上下对称）；中心主题无同级插入带
- 中心主题水平 1/3 → 改侧带；中部 → 成子（守卫 `canMoveOnto`）
- 搜索为**大小写不敏感子串**包含，DFS 先序，含折叠子树；空查询无匹配
- 搜索展开复用 `setCollapsed(ids:collapsed:false)`：一步 Undo；全已展开 no-op 不入栈
- 改侧命令：工具条/⌘←→ 用 `setSide`（仅一级枝）；拖拽落中心半用 `applyRootSide`（提升或改侧）；空白过中线 viaEmpty 用 `setSide`（只改已是中心直接子的枝）
- Model/Command **禁止** import SwiftUI / AppKit / Metal；仅 Foundation
- 文档中文优先；代码标识符英文
- 测试：`xcodebuild test -project YMindApp/YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS' -only-testing:YMindAppTests/<Suite>`

---

## File Structure

```text
YMindApp/YMindApp/
  Model/MindMapModel.swift          # 改：insertSiblings · setSide · applyRootSide · searchMatches · 辅助守卫
  Commands/MindMapCommand.swift     # 改：insertSiblings · setSide · applyRootSide
  Commands/CommandBus.swift         # 改：三个命令分支 + 选中收敛
  Session/DocumentSession.swift     # 改：search 态 · openSearch/closeSearch/runSearch/revealSearchMatch · centerCamera · canSetSide
  Session/Camera.swift              # 改：center(on:viewport:)
  Session/DropIntent.swift          # 新建：DropIntent + resolveDropIntent + canInsertSibling + canMoveOnto + resolveEmptySideIntent（纯函数）
  Render/CanvasMetalView.swift      # 改：手势 intent · 改侧/搜索动作接线
  Render/MetalRenderer.swift        # 改：放置反馈按意图 + 搜索高亮
  ContentView.swift                 # 改：搜索浮层 overlay · 改侧动作 · 相机居中接线
  App/SearchBar.swift               # 新建：搜索浮层 SwiftUI 组件
  App/MainToolbar.swift             # 改：← 左侧 / 右侧 → 按钮
  YMindAppApp.swift                 # 改：菜单 ⌘F/⌘G/⇧⌘G/⌘←/⌘→

YMindApp/YMindAppTests/
  DropIntentTests.swift             # 新建：分区命中 · 守卫 · 空侧意图
  ModelTests.swift                  # 扩：insertSiblings · setSide · applyRootSide · searchMatches
  CommandBusTests.swift             # 扩：三个命令一步 undo/redo
  DocumentSessionTests.swift        # 扩：search 态 · reveal · centerCamera
  CameraTests.swift                 # 扩：center(on:viewport:)
```

---

### Task 1: DropIntent 模型与意图解析（纯函数）

**Files:**
- Create: `YMindApp/YMindApp/Session/DropIntent.swift`
- Test: `YMindApp/YMindAppTests/DropIntentTests.swift`

**Interfaces:**
- Consumes: `LayoutSnapshot`（`frames[UUID]: NodeFrame`，`NodeFrame.rect`/`isRoot`）、`Camera`（`screenToWorld`）、`MindMapModel`（`node(id:)` / `parentId(of:)` / `movableTopLevel` / `isValidDropTarget` / `isDescendant`）
- Produces:
  - `enum DropIntent: Equatable` — `child` / `before` / `after` / `sideLeft` / `sideRight`（后二者带 `viaEmpty: Bool`）
  - `let dropEdgeRatio: CGFloat = 0.28`
  - `func canInsertSibling(_ movingIds: [UUID], anchorId: UUID, model: MindMapModel) -> Bool`
  - `func resolveDropIntent(screenPoint: CGPoint, movingIds: Set<UUID>, snapshot: LayoutSnapshot, camera: Camera, model: MindMapModel) -> DropIntent?`

- [ ] **Step 1: 写失败测试**

新建 `DropIntentTests.swift`：

```swift
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
}
```

> `makeModel` 建 A、B 两个一级枝；A=children[0]、B=children[1]。moving 用 B（与锚点 A 无祖先关系），故 `canInsertSibling` 合法。

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -project YMindApp/YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS' -only-testing:YMindAppTests/DropIntentTests`
Expected: FAIL（`resolveDropIntent` / `DropIntent` 未定义）。

- [ ] **Step 3: 实现**

新建 `DropIntent.swift`：

```swift
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
```

> 说明：`canInsertSibling` 参数用 `[UUID]`（对齐设计 §3.2），`resolveDropIntent` 内部先 `movableTopLevel` 取 tops 再传入。

- [ ] **Step 4: 补足测试（覆盖守卫与分区全分支）**

在 `DropIntentTests.swift` 追加：

```swift
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
```

- [ ] **Step 5: 跑全部 DropIntent 测试确认通过**

Run: `-only-testing:YMindAppTests/DropIntentTests`。Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add YMindApp/YMindApp/Session/DropIntent.swift YMindApp/YMindAppTests/DropIntentTests.swift
git commit -m "$(cat <<'EOF'
feat: DropIntent 分区放置意图与解析

child/before/after/改侧 四类意图 + 空侧意图，对齐原型分区命中。
EOF
)"
```

---

### Task 2: Model — 排序 / 改侧 / 搜索

**Files:**
- Modify: `YMindApp/YMindApp/Model/MindMapModel.swift`
- Test: `YMindApp/YMindAppTests/ModelTests.swift`

**Interfaces:**
- Consumes: 现有 `movableTopLevel` / `node(id:)` / `parentId(of:)` / `indexInParent(of:)` / `pathTo`(private) / `removeWithoutChangingSelection`(private) / `restoreChild` / `mutate(id:_:)`(private) / `attachChild` / `nextSide`(private) / `isDescendant` / `document.root`
- Produces:
  - `enum BeforeAfter { case before, after }`
  - `struct RootSideChange { let sideChanges: [(id: UUID, oldSide: Side?)]; let promotions: [ReparentRecord] }`
  - `@discardableResult func insertSiblings(ids: [UUID], anchorId: UUID, position: BeforeAfter) -> [ReparentRecord]`
  - `@discardableResult func setSide(ids: [UUID], side: Side) -> [(id: UUID, oldSide: Side?)]`
  - `@discardableResult func applyRootSide(ids: [UUID], side: Side) -> RootSideChange`
  - `func searchMatches(query: String) -> [UUID]`

- [ ] **Step 1: 写失败测试**

在 `ModelTests.swift` 追加：

```swift
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
    let aKids = model.node(id: a).map { model.parentId(of: $0.id) } // 仅占位
    _ = aKids
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
    let a = model.insertChild(parentId: root, text: "技术方案", side: .right, at: nil)
    let g = model.insertChild(parentId: a, text: "命中测试", side: nil, at: nil)
    model.setCollapsed(id: a, to: true)

    let ids = model.searchMatches(query: "命中")

    #expect(ids == [g])           // 折叠子树内仍匹配
    #expect(model.searchMatches(query: "技术").contains(a))
    #expect(model.searchMatches(query: "TECH").contains(a))  // 大小写不敏感
    #expect(model.searchMatches(query: "").isEmpty)
    #expect(model.searchMatches(query: "不存在xyz").isEmpty)
}
```

> 注：`insertChild` 会 `selectOnly` 新节点，故测试间模型状态独立（每次 `makeNew`）；`setCollapsed` 用既有 Model 方法。

- [ ] **Step 2: 跑测试确认失败**

Run: `-only-testing:YMindAppTests/ModelTests`。Expected: FAIL（方法缺失）。

- [ ] **Step 3: 实现**

在 `MindMapModel.swift` 文件顶部追加类型：

```swift
enum BeforeAfter { case before, after }

struct RootSideChange: Equatable {
    let sideChanges: [(id: UUID, oldSide: Side?)]
    let promotions: [ReparentRecord]
}
```

在 `final class MindMapModel` 内追加方法（`reparent` 之后、`attachChild` 之前）：

```swift
/// 可搬顶层卸下后按锚点前后插入为连续块（FR-R2）；跨父；新父为中心时 side 继承锚点（否则 nextSide）。
@discardableResult
func insertSiblings(ids: [UUID], anchorId: UUID, position: BeforeAfter) -> [ReparentRecord] {
    let tops = movableTopLevel(ids: Set(ids))
    guard !tops.isEmpty,
          anchorId != document.root.id,
          let anchorParentId = parentId(of: anchorId),
          !tops.contains(anchorId),
          !tops.contains(where: { isDescendant(anchorId, of: $0) }) else {
        return []
    }

    // 严格全序 detach：先按父 id 排序，同父再按下标降序（与 removeMany 一致）。
    let ordered = tops
        .compactMap { id -> (UUID, Int, UUID)? in
            guard let p = parentId(of: id), let i = indexInParent(of: id) else { return nil }
            return (p, i, id)
        }
        .sorted { lhs, rhs in
            if lhs.0 != rhs.0 { return lhs.0.uuidString < rhs.0.uuidString }
            return lhs.1 > rhs.1
        }

    var records: [ReparentRecord] = []
    for (parentId, index, id) in ordered {
        guard let node = node(id: id) else { continue }
        _ = removeWithoutChangingSelection(id: id)
        records.append(ReparentRecord(parentId: parentId, index: index, node: node))
    }
    // 倒序 detach 后反转为原相对序
    records.reverse()

    // anchor 可能已因跨父被搬走（锚点在被搬集被守卫排除，故仍在原父）。
    guard let anchorParentId,
          let anchorIndex = indexInParent(of: anchorId) else {
        // 理论上不可达；保守回滚
        for r in records { restoreChild(parentId: r.parentId, index: r.index, node: r.node) }
        return []
    }
    var insertAt = position == .before ? anchorIndex : anchorIndex + 1
    let anchorNode = node(id: anchorId)
    for r in records {
        var n = r.node
        if anchorParentId == document.root.id {
            n.side = anchorNode?.side ?? nextSide()
        } else {
            n.side = nil
        }
        _ = mutate(id: anchorParentId) { parent in
            parent.children.insert(n, at: min(insertAt, parent.children.count))
        }
        insertAt += 1
    }
    return records
}

/// 仅作用中心直接子，设 side；返回被改节点快照供 Undo。
@discardableResult
func setSide(ids: [UUID], side: Side) -> [(id: UUID, oldSide: Side?)] {
    var changes: [(id: UUID, oldSide: Side?)] = []
    for id in ids where parentId(of: id) == document.root.id {
        guard let node = node(id: id), node.side != side else { continue }
        changes.append((id, node.side))
        _ = mutate(id: id) { $0.side = side }
    }
    return changes
}

/// 中心直接子只改 side；更深提升为一级并设 side；返回撤销记录。
@discardableResult
func applyRootSide(ids: [UUID], side: Side) -> RootSideChange {
    let tops = movableTopLevel(ids: Set(ids))
    var sideChanges: [(id: UUID, oldSide: Side?)] = []
    var promotions: [ReparentRecord] = []
    for id in tops {
        if parentId(of: id) == document.root.id {
            guard let node = node(id: id), node.side != side else { continue }
            sideChanges.append((id, node.side))
            _ = mutate(id: id) { $0.side = side }
        } else {
            guard let p = parentId(of: id),
                  let index = indexInParent(of: id),
                  let node = node(id: id) else { continue }
            _ = removeWithoutChangingSelection(id: id)
            promotions.append(ReparentRecord(parentId: p, index: index, node: node))
            _ = mutate(id: document.root.id) { root in
                var n = node
                n.side = side
                root.children.append(n)
            }
        }
    }
    return RootSideChange(sideChanges: sideChanges, promotions: promotions)
}

/// DFS 先序、大小写不敏感子串包含；含折叠子树；空查询返回空。
func searchMatches(query: String) -> [UUID] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !q.isEmpty else { return [] }
    var ids: [UUID] = []
    func walk(_ node: Node) {
        if node.text.lowercased().contains(q) { ids.append(node.id) }
        for child in node.children { walk(child) }
    }
    walk(document.root)
    return ids
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2。Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add YMindApp/YMindApp/Model/MindMapModel.swift YMindApp/YMindAppTests/ModelTests.swift
git commit -m "$(cat <<'EOF'
feat: Model 排序 / 改侧 / 搜索

insertSiblings 跨父连续块、setSide 仅一级枝、applyRootSide 提升或改侧、searchMatches DFS。
EOF
)"
```

---

### Task 3: Command — insertSiblings / setSide / applyRootSide

**Files:**
- Modify: `YMindApp/YMindApp/Commands/MindMapCommand.swift`
- Modify: `YMindApp/YMindApp/Commands/CommandBus.swift`
- Test: `YMindApp/YMindAppTests/CommandBusTests.swift`

**Interfaces:**
- Consumes: Task 2 `insertSiblings` / `setSide` / `applyRootSide` / `BeforeAfter` / `RootSideChange` / `ReparentRecord`；现有 `model.replaceSelection` / `node(id:)` / `removeWithoutSelection`
- Produces:
  - `MindMapCommand.insertSiblings(ids:[UUID], anchorId:UUID, position:BeforeAfter)`
  - `MindMapCommand.setSide(ids:[UUID], side:Side)`
  - `MindMapCommand.applyRootSide(ids:[UUID], side:Side)`
  - CommandBus 各分支：forward 执行 + undo/redo 一步恢复

- [ ] **Step 1: 写失败测试**

在 `CommandBusTests.swift` 追加：

```swift
@Test func insertSiblings_undoRestoresOriginalParentsAndOrder() {
    let model = MindMapModel.makeNew()
    let bus = CommandBus(model: model)
    let root = model.document.root.id
    let a = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
    let b = model.insertChild(parentId: root, text: "B", side: .left, at: nil)
    let g1 = model.insertChild(parentId: b, text: "G1", side: nil, at: nil)
    let g2 = model.insertChild(parentId: b, text: "G2", side: nil, at: nil)

    bus.execute(.insertSiblings(ids: [g1, g2], anchorId: a, position: .before))
    #expect(model.parentId(of: g1) == root)

    bus.undo()
    #expect(model.parentId(of: g1) == b)
    #expect(model.parentId(of: g2) == b)
    let bKids = model.node(id: b)!.children.map(\.id)
    #expect(bKids == [g1, g2])   // 原父/下标/顺序恢复

    bus.redo()
    #expect(model.parentId(of: g1) == root)
}

@Test func setSide_undoRestoresOldSide() {
    let model = MindMapModel.makeNew()
    let bus = CommandBus(model: model)
    let root = model.document.root.id
    let a = model.insertChild(parentId: root, text: "A", side: .right, at: nil)

    bus.execute(.setSide(ids: [a], side: .left))
    #expect(model.node(id: a)?.side == .left)

    bus.undo()
    #expect(model.node(id: a)?.side == .right)

    bus.redo()
    #expect(model.node(id: a)?.side == .left)
}

@Test func applyRootSide_undoUnpromotes() {
    let model = MindMapModel.makeNew()
    let bus = CommandBus(model: model)
    let root = model.document.root.id
    let a = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
    let g = model.insertChild(parentId: a, text: "G", side: nil, at: nil)

    bus.execute(.applyRootSide(ids: [g], side: .left))
    #expect(model.parentId(of: g) == root)
    #expect(model.node(id: g)?.side == .left)

    bus.undo()
    #expect(model.parentId(of: g) == a)
    #expect(model.node(id: g)?.side == nil)

    bus.redo()
    #expect(model.parentId(of: g) == root)
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `-only-testing:YMindAppTests/CommandBusTests`。Expected: FAIL（命令 case 缺失）。

- [ ] **Step 3: 实现**

`MindMapCommand.swift` 追加三个 case：

```swift
    case insertSiblings(ids: [UUID], anchorId: UUID, position: BeforeAfter)
    case setSide(ids: [UUID], side: Side)
    case applyRootSide(ids: [UUID], side: Side)
```

`CommandBus.swift` 在 `applyForward` 的 `switch` 中追加分支（放在 `moveToParent` 之后）：

```swift
        case let .insertSiblings(ids, anchorId, position):
            let records = model.insertSiblings(ids: ids, anchorId: anchorId, position: position)
            guard !records.isEmpty else { return nil }
            let movedIds = Set(records.map(\.node.id))
            let anchor = movedIds.min { $0.uuidString < $1.uuidString }
            model.replaceSelection(movedIds, anchorId: anchor)
            return Entry(
                undo: {
                    for r in records.sorted(by: { $0.index < $1.index }) {
                        _ = self.model.removeWithoutSelection(id: r.node.id)
                        self.model.restoreChild(parentId: r.parentId, index: r.index, node: r.node)
                    }
                    self.model.replaceSelection(movedIds, anchorId: anchor)
                },
                redo: {
                    _ = self.model.insertSiblings(ids: ids, anchorId: anchorId, position: position)
                    self.model.replaceSelection(movedIds, anchorId: anchor)
                }
            )

        case let .setSide(ids, side):
            let changes = model.setSide(ids: ids, side: side)
            guard !changes.isEmpty else { return nil }
            return Entry(
                undo: {
                    for c in changes {
                        _ = self.model.mutate(id: c.id) { $0.side = c.oldSide }
                    }
                },
                redo: {
                    _ = self.model.setSide(ids: ids, side: side)
                }
            )

        case let .applyRootSide(ids, side):
            let change = model.applyRootSide(ids: ids, side: side)
            guard !change.sideChanges.isEmpty || !change.promotions.isEmpty else { return nil }
            return Entry(
                undo: {
                    for p in change.promotions.sorted(by: { $0.index < $1.index }) {
                        _ = self.model.removeWithoutSelection(id: p.node.id)
                        self.model.restoreChild(parentId: p.parentId, index: p.index, node: p.node)
                    }
                    for c in change.sideChanges {
                        _ = self.model.mutate(id: c.id) { $0.side = c.oldSide }
                    }
                },
                redo: {
                    _ = self.model.applyRootSide(ids: ids, side: side)
                }
            )
```

> `mutate(id:_:)` 当前为 `private`。将 `MindMapModel.mutate(id:_:)` 改为 `func`（移除 `private`）以便 CommandBus 在 undo 中改 side。这是唯一可见性放宽。

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2。Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add YMindApp/YMindApp/Commands/MindMapCommand.swift YMindApp/YMindApp/Commands/CommandBus.swift YMindApp/YMindApp/Model/MindMapModel.swift YMindApp/YMindAppTests/CommandBusTests.swift
git commit -m "$(cat <<'EOF'
feat: 排序/改侧命令一步 Undo

insertSiblings、setSide、applyRootSide 各为命令栈一步，UUID 稳定。
EOF
)"
```

---

### Task 4: Camera 居中 + Session 搜索态

**Files:**
- Modify: `YMindApp/YMindApp/Session/Camera.swift`
- Modify: `YMindApp/YMindApp/Session/DocumentSession.swift`
- Test: `YMindApp/YMindAppTests/CameraTests.swift`
- Test: `YMindApp/YMindAppTests/DocumentSessionTests.swift`

**Interfaces:**
- Consumes: Task 2 `searchMatches`；现有 `model.selectOnly` / `syncSelectionFromModel` / `commandBus.execute` / `snapshot` / `camera`
- Produces:
  - `mutating func Camera.center(on rect: CGRect, viewport: CGSize)` — 保持 scale，矩形中心入视口中心
  - `struct SearchState: Equatable` — `isOpen`/`query`/`matches`/`index`/`currentMatchId`
  - Session: `@Published private(set) var search`、`openSearch()` / `closeSearch()` / `runSearch(query:preferId:)` / `revealSearchMatch(index:)` / `centerCamera(on id:viewport:)` / `canSetSide`

- [ ] **Step 1: 写失败测试**

`CameraTests.swift` 追加：

```swift
@Test func center_keepsScale_andCentersRect() {
    var camera = Camera(translation: CGPoint(x: 100, y: 80), scale: 2)
    let rect = CGRect(x: 50, y: 60, width: 20, height: 10)
    camera.center(on: rect, viewport: CGSize(width: 400, height: 300))

    #expect(camera.scale == 2)                       // 保持缩放
    let c = camera.worldToScreen(rect.center)
    #expect(abs(c.x - 200) < 0.001)                  // 视口水平中心
    #expect(abs(c.y - 150) < 0.001)                  // 视口垂直中心
}
```

`DocumentSessionTests.swift` 追加：

```swift
@Test func search_revealExpandsAncestors_andSelectsMatch() {
    let model = MindMapModel.makeNew()
    let session = DocumentSession(model: model)
    let root = model.document.root.id
    let a = model.insertChild(parentId: root, text: "技术方案", side: .right, at: nil)
    let g = model.insertChild(parentId: a, text: "命中测试", side: nil, at: nil)
    model.setCollapsed(id: a, to: true)
    session.syncSelectionFromModel()

    session.runSearch(query: "命中")
    #expect(session.search.matches == [g])
    #expect(session.search.index == 0)

    session.revealSearchMatch(0)
    #expect(model.node(id: a)?.collapsed == false)   // 祖先展开
    #expect(session.selectedIds == [g])              // 选中收敛
}

@Test func search_noMatch_showsZeroAndNoJump() {
    let session = DocumentSession()
    session.runSearch(query: "不存在xyz")
    #expect(session.search.matches.isEmpty)
    #expect(session.search.index == -1)
    #expect(session.search.currentMatchId == nil)
}

@Test func openSearch_commitsEditingFirst() {
    let session = DocumentSession()
    let root = session.model.document.root.id
    let a = session.model.insertChild(parentId: root, text: "ABC", side: .right, at: nil)
    session.startEditing(a)
    session.draftText = "XYZ"
    session.openSearch()
    #expect(session.editingId == nil)                // 已提交
    #expect(session.model.node(id: a)?.text == "XYZ")
    #expect(session.search.isOpen)
}

@Test func centerCamera_movesToMatch() {
    let session = DocumentSession()
    let root = session.model.document.root.id
    let a = session.model.insertChild(parentId: root, text: "A", side: .right, at: nil)
    session.syncSelectionFromModel()
    session.relayout()
    let before = session.camera.scale
    session.centerCamera(on: a, viewport: CGSize(width: 400, height: 300))
    #expect(session.camera.scale == before)          // 保持缩放
    let frame = session.snapshot.frames[a]!.rect
    let c = session.camera.worldToScreen(frame.center)
    #expect(abs(c.x - 200) < 0.001)
    #expect(abs(c.y - 150) < 0.001)
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `-only-testing:YMindAppTests/CameraTests` 与 `-only-testing:YMindAppTests/DocumentSessionTests`。Expected: FAIL。

- [ ] **Step 3: 实现**

`Camera.swift` 追加：

```swift
    /// 保持当前 scale，平移使给定世界矩形的中心落入视口中心。
    mutating func center(on rect: CGRect, viewport: CGSize) {
        translation = CGPoint(
            x: viewport.width / 2 - rect.midX * scale,
            y: viewport.height / 2 - rect.midY * scale
        )
    }
```

`DocumentSession.swift` 在 `final class` 内追加字段与方法（放在 `cancelCut()` 之后、`pasteToPrimary()` 之前均可）：

```swift
    // MARK: - 搜索

    struct SearchState: Equatable {
        var isOpen = false
        var query = ""
        var matches: [UUID] = []
        var index: Int = -1
        var currentMatchId: UUID? {
            index >= 0 && index < matches.count ? matches[index] : nil
        }
    }

    @Published private(set) var search = SearchState()

    func openSearch() {
        commitEditingIfNeeded()
        search.isOpen = true
        // 已打开：壳层负责聚焦并全选；此处仅保证态
    }

    func closeSearch() {
        search.isOpen = false
    }

    func runSearch(query: String, preferId: UUID? = nil) {
        search.query = query
        search.matches = model.searchMatches(query: query)
        guard !search.matches.isEmpty else {
            search.index = -1
            return
        }
        var idx = 0
        if let preferId, let at = search.matches.firstIndex(of: preferId) {
            idx = at
        }
        revealSearchMatch(idx)
    }

    func revealSearchMatch(_ index: Int) {
        guard !search.matches.isEmpty else { return }
        let n = search.matches.count
        search.index = ((index % n) + n) % n
        let id = search.matches[search.index]

        // 展开通往该节点的全部祖先（复用 setCollapsed：一步 Undo，全已展开 no-op）
        var ancestors: [UUID] = []
        var cur = model.parentId(of: id)
        while let p = cur {
            ancestors.append(p)
            cur = model.parentId(of: p)
        }
        if !ancestors.isEmpty {
            commandBus.execute(.setCollapsed(ids: ancestors, collapsed: false))
        }
        model.selectOnly(id)
        syncSelectionFromModel()
    }

    /// 保持缩放，把命中节点世界矩形中心移到视口中心。
    func centerCamera(on id: UUID, viewport: CGSize) {
        guard let frame = snapshot.frames[id] else { return }
        var cam = camera
        cam.center(on: frame.rect, viewport: viewport)
        camera = cam
    }

    var canSetSide: Bool {
        model.selectedIds.contains { model.parentId(of: $0) == model.document.root.id }
    }
```

> `revealSearchMatch` 中 `setCollapsed` 若 no-op 会返回 nil 不入栈，但 `commandBus.execute` 对 nil 安全（`applyForward` 返回 nil 即不入栈）。展开已展开的祖先 → no-op，不污染 Undo。

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2。Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add YMindApp/YMindApp/Session/Camera.swift YMindApp/YMindApp/Session/DocumentSession.swift YMindApp/YMindAppTests/CameraTests.swift YMindApp/YMindAppTests/DocumentSessionTests.swift
git commit -m "$(cat <<'EOF'
feat: 相机居中 + Session 搜索态

Camera.center 保持缩放居中；SearchState/reveal/runSearch/openSearch/canSetSide。
EOF
)"
```

---

### Task 5: 渲染 — 放置反馈按意图 + 搜索高亮

**Files:**
- Modify: `YMindApp/YMindApp/Render/MetalRenderer.swift`
- Modify: `YMindApp/YMindApp/Render/CanvasMetalView.swift`

**Interfaces:**
- Consumes: Task 1 `DropIntent`；现有 `drawSolid` / `screenRect` / `strokeVertices` / `rectangleQuad` / `segmentQuad` / `solidVertex` / `rgba`
- Produces:
  - `MetalRenderer.draw(...)` 入参改为 `intent: DropIntent?`、新增 `searchHitId: UUID?`
  - 辅助顶点：`horizontalLineQuad` / `edgeInsetQuad` / `verticalLineQuad`

- [ ] **Step 1: 实现绘制**

`MetalRenderer.swift` 的 `draw` 签名改为：

```swift
    func draw(
        in view: MTKView,
        snapshot: LayoutSnapshot,
        camera: Camera,
        selectedIds: Set<UUID>,
        selectionAnchorId: UUID?,
        cutSourceIds: Set<UUID>,
        intent: DropIntent?,
        searchHitId: UUID?,
        marquee: CGRect?
    )
```

在绘制顺序中将 `drawDropHighlight(...)` 替换为 `drawDropFeedback(...)`（意图感知），并在其后新增 `drawSearchHit(...)`：

```swift
        drawDropFeedback(
            snapshot: snapshot, camera: camera, intent: intent,
            encoder: encoder, viewport: &viewport
        )
        drawSearchHit(
            snapshot: snapshot, camera: camera, searchHitId: searchHitId,
            encoder: encoder, viewport: &viewport
        )
```

删除旧 `drawDropHighlight`，新增：

```swift
    /// 放置反馈：child 整节点描边；before/after 弱边框+插入线；side 根镶边/中线引导。
    private func drawDropFeedback(
        snapshot: LayoutSnapshot,
        camera: Camera,
        intent: DropIntent?,
        encoder: MTLRenderCommandEncoder,
        viewport: inout ViewportUniforms
    ) {
        guard let intent else { return }
        let accent = rgba(.controlAccentColor)
        var vertices: [SolidVertex] = []
        switch intent {
        case let .child(targetId):
            guard let frame = snapshot.frames[targetId] else { return }
            let rect = screenRect(frame.rect, camera: camera).insetBy(dx: -3, dy: -3)
            vertices += strokeVertices(rect: rect, thickness: max(2.5, 3 * camera.scale), color: accent)

        case let .before(targetId), let .after(targetId):
            guard let frame = snapshot.frames[targetId] else { return }
            let weakColor = rgba(NSColor.controlAccentColor.withAlphaComponent(0.45))
            let rect = screenRect(frame.rect, camera: camera).insetBy(dx: -3, dy: -3)
            vertices += strokeVertices(rect: rect, thickness: max(1.5, 2 * camera.scale), color: weakColor)
            let y = intent == .before(targetId)
                ? screenRect(frame.rect, camera: camera).minY
                : screenRect(frame.rect, camera: camera).maxY
            vertices += horizontalLineQuad(
                center: CGPoint(x: screenRect(frame.rect, camera: camera).midX, y: y),
                width: max(screenRect(frame.rect, camera: camera).width, 48),
                thickness: 3,
                color: accent
            )

        case let .sideLeft(targetId, viaEmpty), let .sideRight(targetId, viaEmpty):
            guard let frame = snapshot.frames[targetId] else { return }
            if viaEmpty {
                // 中线引导：垂直贯穿线
                let cx = screenRect(frame.rect, camera: camera).midX
                vertices += verticalLineQuad(
                    x: cx,
                    top: 0,
                    bottom: camera.scale > 0 ? 4000 * camera.scale : 0,
                    thickness: 2,
                    color: accent.withAlphaComponent(0.55)
                )
            } else if case .sideLeft = intent {
                let rect = screenRect(frame.rect, camera: camera)
                vertices += edgeInsetQuad(rect: rect, edge: .left, thickness: 6, color: accent)
            } else {
                let rect = screenRect(frame.rect, camera: camera)
                vertices += edgeInsetQuad(rect: rect, edge: .right, thickness: 6, color: accent)
            }
        }
        drawSolid(vertices, encoder: encoder, viewport: &viewport)
    }

    /// 搜索命中：琥珀色描边（对齐原型 .is-search-hit），可与普通选中并存。
    private func drawSearchHit(
        snapshot: LayoutSnapshot,
        camera: Camera,
        searchHitId: UUID?,
        encoder: MTLRenderCommandEncoder,
        viewport: inout ViewportUniforms
    ) {
        guard let searchHitId, let frame = snapshot.frames[searchHitId] else { return }
        let amber = SIMD4<Float>(0.7686, 0.4706, 0.1647, 1)  // #C4782A
        let rect = screenRect(frame.rect, camera: camera).insetBy(dx: -3, dy: -3)
        let vertices = strokeVertices(rect: rect, thickness: max(2, 2.5 * camera.scale), color: amber)
        drawSolid(vertices, encoder: encoder, viewport: &viewport)
    }

    /// 水平插入线：中心点 + 宽度。
    private func horizontalLineQuad(center: CGPoint, width: CGFloat, thickness: CGFloat, color: SIMD4<Float>) -> [SolidVertex] {
        rectangleQuad(
            rect: CGRect(x: center.x - width / 2, y: center.y - thickness / 2, width: width, height: thickness),
            color: color
        )
    }

    /// 垂直贯穿线。
    private func verticalLineQuad(x: CGFloat, top: CGFloat, bottom: CGFloat, thickness: CGFloat, color: SIMD4<Float>) -> [SolidVertex] {
        rectangleQuad(
            rect: CGRect(x: x - thickness / 2, y: top, width: thickness, height: max(bottom - top, 1)),
            color: color
        )
    }

    /// 根节点左右镶边。
    private func edgeInsetQuad(rect: CGRect, edge: EdgeInset, thickness: CGFloat, color: SIMD4<Float>) -> [SolidVertex] {
        switch edge {
        case .left:
            return rectangleQuad(rect: CGRect(x: rect.minX, y: rect.minY, width: thickness, height: rect.height), color: color)
        case .right:
            return rectangleQuad(rect: CGRect(x: rect.maxX - thickness, y: rect.minY, width: thickness, height: rect.height), color: color)
        }
    }

    private enum EdgeInset { case left, right }
```

- [ ] **Step 2: 接线 CanvasMTKView 手势 intent**

`CanvasMetalView.swift`：
- `CanvasPointerGesture.drag(movingIds:dropTarget:lastPoint:)` → `.drag(movingIds:intent:lastPoint:)`；`currentDropTargetId` → `currentDropIntent`（`if case let .drag(_, intent, _) = self { return intent }`）。
- `draw(...)` 调用：`intent: gesture.currentDropIntent`、新增 `searchHitId: session.search.currentMatchId`。
- `continuePointerGesture` 的 `.drag` 分支：`computeDropTarget` → `computeDropIntent`，返回 `resolveDropIntent(...)`。
- `pendingDrag → .drag` 初始 intent 用同一解析。
- `endPointerGesture` 的 `.drag`：按意图映射动作（child→move；before/after→insertSiblings；sideLeft/right viaEmpty→setSide；sideLeft/right 非 viaEmpty→applyRootSide）。
- 新增动作回调：`insertSiblings(_:anchorId:position:)`、`setSide(_:side:)`、`applyRootSide(_:side:)` 进 `CanvasActions`。

具体映射（在 `endPointerGesture` 中替代原 `if let dropTarget { actions.move(...) }`）：

```swift
        case .drag(let movingIds, let intent, _):
            if let intent {
                let ids = Array(movingIds)
                switch intent {
                case .child(let targetId):
                    actions.move(ids, targetId)
                case .before(let anchorId):
                    actions.insertSiblings(ids, anchorId, .before)
                case .after(let anchorId):
                    actions.insertSiblings(ids, anchorId, .after)
                case .sideLeft(_, let viaEmpty):
                    if viaEmpty { actions.setSide(ids, .left) }
                    else { actions.applyRootSide(ids, .left) }
                case .sideRight(_, let viaEmpty):
                    if viaEmpty { actions.setSide(ids, .right) }
                    else { actions.applyRootSide(ids, .right) }
                }
            }
```

- [ ] **Step 3: 编译验证**

Run: `xcodebuild build -project YMindApp/YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED（此时 `insertSiblings`/`setSide`/`applyRootSide` 动作回调尚未在 ContentView 接线——需在 Task 6 一并补，否则编译错误。**若此步骤编译失败，把 Task 6 的 CanvasActions 接线先做**，即此 Task 与 Task 6 中画布动作声明部分须同步落地以保持可编译）。

> 依赖说明：`CanvasActions` 新增闭包必须有默认空实现（与现有 `move` 等一致），故在 Task 5 声明即可编译，ContentView 在 Task 6 接线。

- [ ] **Step 4: Commit**

```bash
git add YMindApp/YMindApp/Render/MetalRenderer.swift YMindApp/YMindApp/Render/CanvasMetalView.swift
git commit -m "$(cat <<'EOF'
feat: 渲染放置反馈按意图 + 搜索高亮

插入线/根镶边/中线引导/搜索高亮；手势 intent 接线。
EOF
)"
```

---

### Task 6: 壳层 — 搜索浮层 + 改侧工具条 + 快捷键

**Files:**
- Create: `YMindApp/YMindApp/App/SearchBar.swift`
- Modify: `YMindApp/YMindApp/ContentView.swift`
- Modify: `YMindApp/YMindApp/App/MainToolbar.swift`
- Modify: `YMindApp/YMindApp/YMindAppApp.swift`

**Interfaces:**
- Consumes: Task 4 `search` / `openSearch` / `closeSearch` / `runSearch` / `revealSearchMatch` / `centerCamera` / `canSetSide`；Task 5 `CanvasActions` 新动作（`insertSiblings` / `setSide` / `applyRootSide`）
- Produces: 搜索浮层 SwiftUI 组件；工具条改侧按钮；菜单与快捷键

- [ ] **Step 1: 搜索浮层组件**

新建 `SearchBar.swift`：

```swift
import SwiftUI

struct SearchBar: View {
    @ObservedObject var session: DocumentSession
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Label("搜索", systemImage: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索主题…", text: Binding(
                get: { session.search.query },
                set: { session.runSearch(query: $0) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 200)
            .focused($isFocused)
            .onAppear { isFocused = true }
            .onSubmit { session.revealSearchMatch(session.search.index + 1) }
            .onExitCommand { session.closeSearch() }

            Text("\(session.search.index + 1) / \(session.search.matches.count)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityLabel("搜索计数")

            Button { session.revealSearchMatch(session.search.index - 1) } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(session.search.matches.isEmpty)
            .help("上一项（⇧Enter）")

            Button { session.revealSearchMatch(session.search.index + 1) } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(session.search.matches.isEmpty)
            .help("下一项（Enter）")

            Button { session.closeSearch() } label: {
                Image(systemName: "xmark")
            }
            .help("关闭（Esc）")
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding()
        .onChange(of: session.search.currentMatchId) { _, newId in
            guard let newId else { return }
            if let size = windowSize() {
                session.centerCamera(on: newId, viewport: size)
            }
        }
    }

    private func windowSize() -> CGSize? {
        NSApp.keyWindow?.contentView?.bounds.size
    }
}
```

- [ ] **Step 2: ContentView 接线**

`ContentView.swift`：
- ZStack 顶部、`NodeEditorOverlay` 之后新增：

```swift
                if session.search.isOpen {
                    SearchBar(session: session)
                }
```

- `CanvasActions` 闭包新增接线（放在 `move` 之后）：

```swift
                        move: move,
                        insertSiblings: { ids, anchorId, position in
                            if session.editingId != nil { commitEditing() }
                            session.commandBus.execute(.insertSiblings(ids: ids, anchorId: anchorId, position: position))
                        },
                        setSide: { ids, side in
                            if session.editingId != nil { commitEditing() }
                            session.commandBus.execute(.setSide(ids: ids, side: side))
                        },
                        applyRootSide: { ids, side in
                            if session.editingId != nil { commitEditing() }
                            session.commandBus.execute(.applyRootSide(ids: ids, side: side))
                        },
```

- 改侧动作：`ContentView` 增加 `setSide(_ side: Side)`（内部 `commitEditingIfNeeded` 后 `execute(.setSide(ids: Array(session.selectedIds), side: side))`），供工具条与菜单调用。
- 相机居中：`SearchBar` 内 `onChange` 处理（Step 1 已含）。

- [ ] **Step 3: 工具条改侧按钮**

`MainToolbar.swift` 增字段与按钮（剪贴板组之后、`secondaryAction` 之前）：

```swift
    let canSetSide: Bool
    let setSideLeft: () -> Void
    let setSideRight: () -> Void
```

在 `ToolbarItemGroup(placement: .automatic)` 内剪贴板按钮之后：

```swift
            Button(action: setSideLeft) {
                Label("← 左侧", systemImage: "arrow.left.to.line")
            }
            .disabled(!canSetSide)
            .help("放到左侧（⌘←）")

            Button(action: setSideRight) {
                Label("右侧 →", systemImage: "arrow.right.to.line")
            }
            .disabled(!canSetSide)
            .help("放到右侧（⌘→）")
```

`ContentView` 的 `.toolbar` 调用处补传：

```swift
                    canSetSide: session.canSetSide,
                    setSideLeft: { setSide(.left) },
                    setSideRight: { setSide(.right) },
```

- [ ] **Step 4: 菜单与快捷键**

`YMindAppApp.swift` `DocumentCommands` 追加搜索组与改侧组：

```swift
        CommandGroup(after: .undoRedo) {
            Button("搜索…") {
                session.openSearch()
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("查找下一个") {
                session.revealSearchMatch(session.search.index + 1)
            }
            .keyboardShortcut("g", modifiers: .command)

            Button("查找上一个") {
                session.revealSearchMatch(session.search.index - 1)
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])

            Divider()

            Button("移到左侧") {
                _ = setSide(session, .left)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(!session.canSetSide)

            Button("移到右侧") {
                _ = setSide(session, .right)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(!session.canSetSide)
        }
```

新增辅助：

```swift
    @discardableResult
    private func setSide(_ session: DocumentSession, _ side: Side) -> Bool {
        session.commitEditingIfNeeded()
        let ids = Array(session.selectedIds)
        guard session.canSetSide else { return false }
        session.commandBus.execute(.setSide(ids: ids, side: side))
        return true
    }
```

> `CanvasMetalView.keyDown` 中已有 ⌘C/X/V/A/. 处理；⌘←/⌘→ 经菜单项触发（菜单项优先于 canvas keyDown）。为一致，canvas keyDown 也可补 `case .leftArrow/.rightArrow` 但非必需——菜单项已覆盖。

- [ ] **Step 5: 编译并跑全量测试**

Run: `xcodebuild build -project YMindApp/YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED。

Run: `xcodebuild test -project YMindApp/YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS' -only-testing:YMindAppTests`
Expected: 全部 PASS（含既有回归）。

- [ ] **Step 6: Commit**

```bash
git add YMindApp/YMindApp/App/SearchBar.swift YMindApp/YMindApp/ContentView.swift YMindApp/YMindApp/App/MainToolbar.swift YMindApp/YMindApp/YMindAppApp.swift
git commit -m "$(cat <<'EOF'
feat: 搜索浮层 + 改侧工具条 + 快捷键

⌘F/⌘G 搜索跳转、⌘←/⌘→ 改侧、工具条改侧按钮、CanvasActions 接线。
EOF
)"
```

---

### Task 7: 手测对照三份 PRD 验收表

**Files:** 无（手测清单）

**Interfaces:** 无（验证已实现功能）

- [ ] **Step 1: 启动 App 手测 Reorder（7 条）**

```bash
xcodebuild build -project YMindApp/YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS' && open build/.../YMind.app
```

逐条核对：中部成子 / 上边插前同父 / 下边插后同父 / 中心边缘仍成子 / 自身上下边无意图 / 跨父插前改父+顺序+侧继承 / 多选连续块相对序。

- [ ] **Step 2: 手测 Search（6 条）**

⌘F 聚焦 / 折叠内命中展开+居中选中 / 多项 Enter 循环 / 无匹配 0/0 / Esc 关闭 / 搜索框 Enter 不新增同级。

- [ ] **Step 3: 手测 Side（7 条）**

选一级枝 ⌘→ 移右 / 工具条「← 左侧」/ 一级枝拖过中线空白改侧仍一级 / 拖中心左半一级+left / 中心中部成子 / 深层拖空白不改侧 / 多选含一级+深层点右侧仅一级改侧。

- [ ] **Step 4: 记录结果**

手测通过后，在 `docs/架构现状.md` 追加本增量小节（中文），并确认三份 PRD 验收要点全部满足。

- [ ] **Step 5: Commit**

```bash
git add docs/架构现状.md
git commit -m "docs: 同级排序+搜索+改侧已实现"
```

---

## 自审

**Spec 覆盖核对：**
- §3 DropIntent 解析 → Task 1
- §4 Model/命令 → Task 2、Task 3
- §5 Session 搜索态 → Task 4
- §6 手势 intent + 相机居中 → Task 5、Task 4
- §7 渲染（插入线/镶边/中线/搜索高亮）→ Task 5
- §8 壳层（搜索浮层/工具条/快捷键）→ Task 6
- §9 边界与错误行为 → 分布在 Task 1（守卫）、Task 3（Undo）、Task 6（no-op）
- §10 测试与验收 → Task 1/2/3/4 单测 + Task 7 手测

**占位符扫描：** 无 TBD/TODO；所有代码步骤含完整实现。

**类型一致性：** `DropIntent` / `BeforeAfter` / `RootSideChange` / `SearchState` / `canSetSide` / `revealSearchMatch` / `centerCamera(on:viewport:)` 在后续任务中命名与定义一致；`insertSiblings(ids:anchorId:position:)` 签名在 Task 2/3/5/6 统一。`mutate(id:_:)` 可见性放宽（Task 3 说明）在 Task 3 Step 3 声明。
