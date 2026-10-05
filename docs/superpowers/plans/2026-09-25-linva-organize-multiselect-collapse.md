# Linva 整理效率（多选与画布折叠）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有 `LinvaApp` 上将单选升为多选（含框选），工具条严格模式与批量删除入 Undo，折叠入口迁至 Metal 分叉控件（＋ / −N），对齐 PRD 与原型。

**Architecture:** 沿用 v1 分层。`MindMapModel` 持有 `selectedIds` + `selectionAnchorId`；`LayoutSnapshot.branchToggles` 由 `RadialLayout` 产出；`MetalRenderer` 绘制多选描边与分叉控件；`CanvasMTKView` 手势改为「toggle → 节点 → 空格平移 / 默认框选」。不做 Session 大拆、不做拖拽/剪贴板。

**Tech Stack:** Swift、SwiftUI、AppKit（`NSEvent` 修饰键 / 空格）、MetalKit、Swift Testing；工程 `LinvaApp/`（`PBXFileSystemSynchronizedRootGroup`）。

**Spec:** `docs/superpowers/specs/2026-09-25-linva-organize-multiselect-collapse-design.md`  
**PRD:** `docs/prds/prd-linva-organize-2026-09-25/prd.md`  
**原型对照:** `prototype/app.js`（选中 / 框选阈值 4pt / 分叉 gap≈18）

## Global Constraints

- 平台：macOS（工程 `MACOSX_DEPLOYMENT_TARGET = 26.4`）
- 选中 / 相机 **不入** `.linva`；文件格式 version 不变
- 空白拖 = 框选；空格+拖 = 平移；不提供偏好切换
- 分叉极性：展开显示 **＋**（点即折叠）；折叠显示 **−N**（点即展开）
- 多选时工具条禁用子主题/同级；折叠按钮从工具条移除
- 批量删除 / `setCollapsed` 各为命令栈 **一步**
- Model/Command **禁止** import SwiftUI / AppKit / Metal
- 文档中文优先；代码标识符英文
- 测试：`xcodebuild test -project LinvaApp/LinvaApp.xcodeproj -scheme LinvaApp -destination 'platform=macOS' -only-testing:LinvaAppTests/<Suite>`

---

## File Structure

```text
LinvaApp/LinvaApp/
  Model/MindMapModel.swift              # 改：selectedIds / 锚点 / 批量删与折叠
  Commands/MindMapCommand.swift         # 改：delete(ids) · setCollapsed
  Commands/CommandBus.swift             # 改：新命令分支
  Layout/LayoutConstants.swift          # 改：branchToggleGap / hitRadius
  Layout/LayoutSnapshot.swift           # 改：BranchToggle + branchToggles
  Layout/RadialLayout.swift             # 改：生成 toggles；根折叠仍出控件
  Session/DocumentSession.swift         # 改：镜像 selectedIds / anchor
  App/MainToolbar.swift                 # 改：严格模式 · 已选 N · 去折叠
  ContentView.swift                     # 改：接线多选 · 快捷键批量折叠
  Render/MetalRenderer.swift            # 改：多选描边 · 分叉控件；停用角标主路径
  Render/CanvasMetalView.swift          # 改：命中优先级 · 框选 · 空格平移
  Render/CanvasHitTesting.swift         # 新建（可选）：hitTest / marqueeIntersect 纯函数

LinvaApp/LinvaAppTests/
  ModelTests.swift                      # 改/扩
  CommandBusTests.swift                 # 扩
  RadialLayoutTests.swift               # 扩 toggles；角标断言改为 toggle
  HitTestTests.swift                    # 扩 toggle 优先与框选求交
```

---

### Task 1: Model — 选中集 API

**Files:**
- Modify: `LinvaApp/LinvaApp/Model/MindMapModel.swift`
- Modify: `LinvaApp/LinvaAppTests/ModelTests.swift`

**Interfaces:**
- Consumes: 现有树 API（`node` / `parent` / `pathTo`）
- Produces:
  - `var selectedIds: Set<UUID>`
  - `var selectionAnchorId: UUID?`
  - `var primarySelectedId: UUID?` — 锚点若在集内则用之，否则 `selectedIds.min(by: { $0.uuidString < $1.uuidString })`
  - `func selectOnly(_ id: UUID?)` — 替换原 `select`；`nil` 清空集与锚点
  - `func toggleInSelection(_ id: UUID)` — ⌘ 加减选；加入时锚点= id；移除后若锚点被移出则锚点= `primarySelectedId`
  - `func selectSiblingRange(to id: UUID)` — 同父则连续兄弟，异父则 `selectOnly(id)`
  - `func replaceSelection(_ ids: Set<UUID>, anchorId: UUID?)` — 框选/⌘A；只保留仍存在于树中的 id
  - `func clearSelection()`
  - 插入/删除后：`insertChild` / `insertSibling` 仍 `selectOnly(newId)`；`remove` 后 `selectOnly(parentId)`（批量删在 Task 3）

- [ ] **Step 1: 写失败测试 — 选中集与 Shift 同父**

在 `ModelTests.swift` 追加（并改现有 `selectedId` 断言为 `selectedIds` / `primarySelectedId`）：

```swift
@Test func makeNew_hasSingleRootSelected() {
    let model = MindMapModel.makeNew()
    #expect(model.selectedIds == [model.document.root.id])
    #expect(model.selectionAnchorId == model.document.root.id)
    #expect(model.primarySelectedId == model.document.root.id)
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

@Test func selectNil_clearsSelection() {
    let model = MindMapModel.makeNew()
    model.selectOnly(nil)
    #expect(model.selectedIds.isEmpty)
    #expect(model.selectionAnchorId == nil)
    #expect(model.primarySelectedId == nil)
}
```

把原 `remove_selectsParent` 中 `#expect(model.selectedId == rootId)` 改为 `#expect(model.selectedIds == [rootId])`。

- [ ] **Step 2: 跑测试确认失败**

Run:

```bash
xcodebuild test -project LinvaApp/LinvaApp.xcodeproj -scheme LinvaApp \
  -destination 'platform=macOS' -only-testing:LinvaAppTests/MindMapModel
```

Expected: 编译失败或断言失败（`selectedId` 不存在 / 新方法缺失）。

- [ ] **Step 3: 实现选中集**

替换 `MindMapModel` 选中相关部分（保留树变更 API，仅改选中字段与方法）：

```swift
final class MindMapModel {
    var document: MindMapDocument
    var selectedIds: Set<UUID> = []
    var selectionAnchorId: UUID?

    var primarySelectedId: UUID? {
        if let selectionAnchorId, selectedIds.contains(selectionAnchorId) {
            return selectionAnchorId
        }
        return selectedIds.min { $0.uuidString < $1.uuidString }
    }

    init(document: MindMapDocument, selectedId: UUID? = nil) {
        self.document = document
        let initial = selectedId ?? document.root.id
        selectedIds = [initial]
        selectionAnchorId = initial
    }

    static func makeNew() -> MindMapModel {
        let doc = MindMapDocument.blank()
        return MindMapModel(document: doc, selectedId: doc.root.id)
    }

    func selectOnly(_ id: UUID?) {
        guard let id else {
            selectedIds = []
            selectionAnchorId = nil
            return
        }
        guard node(id: id) != nil else { return }
        selectedIds = [id]
        selectionAnchorId = id
    }

    /// 兼容旧调用点：等价于 selectOnly
    func select(_ id: UUID?) { selectOnly(id) }

    func clearSelection() { selectOnly(nil) }

    func toggleInSelection(_ id: UUID) {
        guard node(id: id) != nil else { return }
        if selectedIds.contains(id) {
            selectedIds.remove(id)
            if selectionAnchorId == id {
                selectionAnchorId = primarySelectedId
            }
        } else {
            selectedIds.insert(id)
            selectionAnchorId = id
        }
    }

    func selectSiblingRange(to id: UUID) {
        guard node(id: id) != nil else { return }
        guard let anchor = selectionAnchorId,
              let anchorParent = parentId(of: anchor),
              let targetParent = parentId(of: id),
              anchorParent == targetParent,
              let parent = node(id: anchorParent) else {
            selectOnly(id)
            return
        }
        let ids = parent.children.map(\.id)
        guard let i0 = ids.firstIndex(of: anchor),
              let i1 = ids.firstIndex(of: id) else {
            selectOnly(id)
            return
        }
        let lo = min(i0, i1)
        let hi = max(i0, i1)
        selectedIds = Set(ids[lo...hi])
        // 锚点保持原锚点，便于连续 Shift
    }

    func replaceSelection(_ ids: Set<UUID>, anchorId: UUID?) {
        selectedIds = Set(ids.filter { node(id: $0) != nil })
        if let anchorId, selectedIds.contains(anchorId) {
            selectionAnchorId = anchorId
        } else {
            selectionAnchorId = primarySelectedId
        }
    }

    // insertChild 末尾改为：
    //   selectOnly(newId)
    // remove 成功后改为：
    //   selectOnly(parentId)
}
```

- [ ] **Step 4: 跑测试确认通过**

同 Step 2 命令。Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Model/MindMapModel.swift LinvaApp/LinvaAppTests/ModelTests.swift
git commit -m "$(cat <<'EOF'
feat: Model 选中集与锚点 API

为多选/Shift 连选提供 selectedIds 与 selectionAnchorId。
EOF
)"
```

---

### Task 2: Session + 严格工具条（仍单删）

**Files:**
- Modify: `LinvaApp/LinvaApp/Session/DocumentSession.swift`
- Modify: `LinvaApp/LinvaApp/App/MainToolbar.swift`
- Modify: `LinvaApp/LinvaApp/ContentView.swift`
- Modify: `LinvaApp/LinvaApp/Render/CanvasMetalView.swift`（draw 暂用 `primarySelectedId`）
- Modify: `LinvaApp/LinvaApp/Render/MetalRenderer.swift`（签名可暂留 `selectedId`，由调用方传 `primarySelectedId`）

**Interfaces:**
- Consumes: Task 1 Model API
- Produces:
  - Session：`@Published selectedIds: Set<UUID>`、`selectionAnchorId`；`selectOnly` / `toggleInSelection` / `selectSiblingRange` / `replaceSelection` / `clearSelection`；`var primarySelectedId: UUID?` 转发
  - `MainToolbar`：去掉折叠按钮；增加 `selectionCount: Int`、`canAddChild`、`canAddSibling`、`canDelete`；多选时显示「已选 N」
  - ContentView：`addChild`/`addSibling` 仅当 `!multi && primary != nil`；删除仍走单 `delete(id:)`（Task 3 再批量）

- [ ] **Step 1: 写失败测试 — Session 镜像选中集**

若尚无合适套件，在 `DocumentSessionTests.swift` 追加：

```swift
@Test func selectOnly_mirrorsSelectedIds() {
    let session = DocumentSession()
    let root = session.model.document.root.id
    let child = session.model.insertChild(parentId: root, text: "A", side: .right, at: nil)
    session.selectOnly(child)
    #expect(session.selectedIds == [child])
    #expect(session.selectionAnchorId == child)
    session.toggleInSelection(root)
    #expect(session.selectedIds == [child, root])
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `-only-testing:LinvaAppTests/DocumentSessionTests`（或含新用例的 suite）。Expected: 方法缺失失败。

- [ ] **Step 3: 实现 Session 镜像**

```swift
@Published private(set) var selectedIds: Set<UUID> = []
@Published private(set) var selectionAnchorId: UUID?

var primarySelectedId: UUID? { model.primarySelectedId }

func syncSelectionFromModel() {
    selectedIds = model.selectedIds
    selectionAnchorId = model.selectionAnchorId
}

func selectOnly(_ id: UUID?) {
    model.selectOnly(id)
    syncSelectionFromModel()
}

func toggleInSelection(_ id: UUID) {
    model.toggleInSelection(id)
    syncSelectionFromModel()
}

func selectSiblingRange(to id: UUID) {
    model.selectSiblingRange(to: id)
    syncSelectionFromModel()
}

func replaceSelection(_ ids: Set<UUID>, anchorId: UUID?) {
    model.replaceSelection(ids, anchorId: anchorId)
    syncSelectionFromModel()
}

func clearSelection() {
    model.clearSelection()
    syncSelectionFromModel()
}

// 删除旧 select(_:) 或令其调用 selectOnly
// newDocument / load：model.selectOnly(doc.root.id); syncSelectionFromModel()
// wireCommandBus onChange：syncSelectionFromModel()
// startEditing：selectOnly(id) 后进入编辑
```

- [ ] **Step 4: 改 MainToolbar**

```swift
struct MainToolbar: ToolbarContent {
    let selectionCount: Int
    let canAddChild: Bool
    let canAddSibling: Bool
    let canDelete: Bool
    let zoomPercent: Int
    let addChild: () -> Void
    let addSibling: () -> Void
    let delete: () -> Void
    let zoomOut: () -> Void
    let zoomIn: () -> Void
    let fit: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            if selectionCount > 1 {
                Text("已选 \(selectionCount)")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("已选 \(selectionCount) 个主题")
            }
            Button(action: addChild) {
                Label("子主题", systemImage: "arrow.turn.down.right")
            }
            .disabled(!canAddChild)
            .help("添加子主题（Tab）")

            Button(action: addSibling) {
                Label("同级主题", systemImage: "plus.rectangle.on.rectangle")
            }
            .disabled(!canAddSibling)
            .help("添加同级主题（Return）")

            Button(role: .destructive, action: delete) {
                Label("删除", systemImage: "trash")
            }
            .disabled(!canDelete)
            .help("删除主题（Delete）")
        }
        // zoom 组保持不变
        ...
    }
}
```

ContentView 计算：

```swift
private var isMulti: Bool { session.selectedIds.count > 1 }
private var canAddChild: Bool { !isMulti && session.primarySelectedId != nil }
private var canAddSibling: Bool {
    guard !isMulti, let id = session.primarySelectedId else { return false }
    return id != session.model.document.root.id
}
private var canDelete: Bool {
    session.selectedIds.contains { $0 != session.model.document.root.id }
}
```

`addChild` / `addSibling`：用 `primarySelectedId`；多选时直接 return。  
`toggleCollapse` 方法与工具条折叠入口删除（分叉在 Task 4–5）。  
Canvas `draw`：`selectedId: session.primarySelectedId`。  
`handleSelection`：暂时仍 `selectOnly`（修饰键在 Task 6）。

- [ ] **Step 5: 编译并跑相关测试**

```bash
xcodebuild test -project LinvaApp/LinvaApp.xcodeproj -scheme LinvaApp \
  -destination 'platform=macOS' \
  -only-testing:LinvaAppTests/DocumentSessionTests \
  -only-testing:LinvaAppTests/MindMapModel
```

Expected: PASS；App 能编译运行；多选暂无法从 UI 形成，但单选工具条无折叠按钮。

- [ ] **Step 6: Commit**

```bash
git add LinvaApp/LinvaApp/Session/DocumentSession.swift \
  LinvaApp/LinvaApp/App/MainToolbar.swift \
  LinvaApp/LinvaApp/ContentView.swift \
  LinvaApp/LinvaApp/Render/CanvasMetalView.swift
git commit -m "$(cat <<'EOF'
feat: Session 多选镜像与严格工具条

去掉工具条折叠；多选时禁用增节点并显示已选 N。
EOF
)"
```

---

### Task 3: 批量删除命令

**Files:**
- Modify: `LinvaApp/LinvaApp/Model/MindMapModel.swift`
- Modify: `LinvaApp/LinvaApp/Commands/MindMapCommand.swift`
- Modify: `LinvaApp/LinvaApp/Commands/CommandBus.swift`
- Modify: `LinvaApp/LinvaApp/ContentView.swift`
- Modify: `LinvaApp/LinvaAppTests/CommandBusTests.swift`
- Modify: `LinvaApp/LinvaAppTests/ModelTests.swift`

**Interfaces:**
- Consumes: Task 1 选中集
- Produces:
  - `MindMapModel.topLevelDeletableIds(from ids: Set<UUID>) -> [UUID]` — 非根；若祖先也在 `ids` 中则跳过该 id
  - `MindMapModel.removeMany(ids: [UUID]) -> [(parentId: UUID, index: Int, node: Node)]` — 按**从深到浅或按原父下标从大到小**删除，避免下标错乱；删后 `selectOnly` 第一个仍存在的父，否则清空
  - `MindMapCommand.delete(ids: [UUID])`
  - 保留 `delete(id:)` 实现为 `delete(ids: [id])` 或内部共用
  - ContentView `deleteSelected` → `execute(.delete(ids: Array(session.selectedIds)))`

- [ ] **Step 1: 写失败测试**

```swift
@Test func topLevelDeletableIds_skipsDescendantsWhenAncestorSelected() {
    let model = MindMapModel.makeNew()
    let root = model.document.root.id
    let p = model.insertChild(parentId: root, text: "P", side: .right, at: nil)
    let c = model.insertChild(parentId: p, text: "C", side: nil, at: nil)
    let ids = model.topLevelDeletableIds(from: [p, c, root])
    #expect(ids == [p])
}

@Test func deleteMany_undo_restoresSubtreesInOneStep() {
    let model = MindMapModel.makeNew()
    let bus = CommandBus(model: model)
    let root = model.document.root.id
    let a = model.insertChild(parentId: root, text: "A", side: .left, at: nil)
    let b = model.insertChild(parentId: root, text: "B", side: .right, at: nil)
    bus.clearHistory()
    bus.execute(.delete(ids: [a, b]))
    #expect(model.document.root.children.isEmpty)
    bus.undo()
    #expect(Set(model.document.root.children.map(\.id)) == [a, b])
    #expect(model.selectedIds == [a, b] || model.selectedIds.isSuperset(of: [a, b]))
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `-only-testing:LinvaAppTests/CommandBus` 与 Model suite。Expected: FAIL。

- [ ] **Step 3: 实现 Model + Command**

```swift
// MindMapModel
func topLevelDeletableIds(from ids: Set<UUID>) -> [UUID] {
    let rootId = document.root.id
    return ids.filter { id in
        guard id != rootId, node(id: id) != nil else { return false }
        var parent = parentId(of: id)
        while let p = parent {
            if ids.contains(p) { return false }
            parent = parentId(of: p)
        }
        return true
    }
}

func removeMany(ids: [UUID]) -> [(parentId: UUID, index: Int, node: Node)] {
    let ordered = ids.compactMap { id -> (UUID, Int, UUID)? in
        guard let p = parentId(of: id), let i = indexInParent(of: id) else { return nil }
        return (p, i, id)
    }
    // 同一父内按下标降序删，避免移位
    .sorted { lhs, rhs in
        if lhs.0 == rhs.0 { return lhs.1 > rhs.1 }
        return lhs.2.uuidString < rhs.2.uuidString
    }

    var removed: [(parentId: UUID, index: Int, node: Node)] = []
    var parentCandidates: [UUID] = []
    for (_, _, id) in ordered {
        if let r = remove(id: id) {
            // remove 会 selectOnly(parent) — 批量结束后再统一选中
            removed.append(r)
            parentCandidates.append(r.parentId)
        }
    }
    if let keep = parentCandidates.first(where: { node(id: $0) != nil }) {
        selectOnly(keep)
    } else {
        clearSelection()
    }
    return removed
}
```

注意：`remove` 每次改选中；`removeMany` 应在循环内用**不改选中**的底层删除，或循环后覆盖选中。推荐抽 `removeWithoutChangingSelection` 私有方法，或循环用 mutate 后一次性 `selectOnly`。

```swift
// MindMapCommand
case delete(ids: [UUID])
// 可保留 case delete(id: UUID) 并在 CommandBus 转成 ids

// CommandBus
case let .delete(ids):
    let tops = model.topLevelDeletableIds(from: Set(ids))
    guard !tops.isEmpty else { return nil }
    let removed = model.removeMany(ids: tops)
    guard !removed.isEmpty else { return nil }
    let restoredSelection = Set(removed.map(\.node.id))
    return Entry(
        undo: {
            // 按原 index 升序插回，同父从低到高
            for item in removed.sorted(by: { $0.index < $1.index }) {
                self.model.restoreChild(
                    parentId: item.parentId,
                    index: item.index,
                    node: item.node
                )
            }
            self.model.replaceSelection(restoredSelection, anchorId: restoredSelection.min { $0.uuidString < $1.uuidString })
        },
        redo: { _ = self.model.removeMany(ids: tops) }
    )
```

单删路径：`.delete(id:)` 改为调用同一逻辑，或 ContentView 只发 `delete(ids:)`。

ContentView:

```swift
private func deleteSelected() {
    if session.editingId != nil { commitEditing() }
    let ids = Array(session.selectedIds)
    guard ids.contains(where: { $0 != session.model.document.root.id }) else { return }
    session.commandBus.execute(.delete(ids: ids))
}
```

- [ ] **Step 4: 跑测试确认通过**

Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Model/MindMapModel.swift \
  LinvaApp/LinvaApp/Commands/MindMapCommand.swift \
  LinvaApp/LinvaApp/Commands/CommandBus.swift \
  LinvaApp/LinvaApp/ContentView.swift \
  LinvaApp/LinvaAppTests/CommandBusTests.swift \
  LinvaApp/LinvaAppTests/ModelTests.swift
git commit -m "$(cat <<'EOF'
feat: 批量删除命令一步 Undo

父子同选只删顶层；根始终保留。
EOF
)"
```

---

### Task 4: Layout — `BranchToggle` 生成

**Files:**
- Modify: `LinvaApp/LinvaApp/Layout/LayoutConstants.swift`
- Modify: `LinvaApp/LinvaApp/Layout/LayoutSnapshot.swift`
- Modify: `LinvaApp/LinvaApp/Layout/RadialLayout.swift`
- Modify: `LinvaApp/LinvaAppTests/RadialLayoutTests.swift`
- Modify: 所有 `LayoutSnapshot(frames:edges:)` 调用处，增加 `branchToggles: []`（或给 init 默认参数）

**Interfaces:**
- Consumes: 布局后的 `frames` + 树节点 `children` / `collapsed`
- Produces:

```swift
struct BranchToggle: Equatable {
    let nodeId: UUID
    let side: Side
    let center: CGPoint
    let collapsed: Bool
    let hiddenCount: Int
}

struct LayoutSnapshot: Equatable {
    let frames: [UUID: NodeFrame]
    let edges: [EdgeGeometry]
    let branchToggles: [BranchToggle]
}

// LayoutConstants
static let branchToggleGap: CGFloat = 18
static let branchToggleVisualRadius: CGFloat = 11
static let branchToggleHitRadius: CGFloat = 14
```

生成规则（对齐原型 `toggleSpec`）：
- 仅 `node.children` 非空时生成
- 非根：`side` = 节点 `frame.side`（left/right），`center.x = frame.center.x + dir * (width/2 + gap)`，`center.y = frame.center.y`，`dir = side==.left ? -1 : 1`
- 根：若 `collapsed || hasLeft` 出 left；若 `collapsed || hasRight` 出 right；即使 `root.collapsed` 早退不放子节点，**仍要**在 return 前写入 toggles
- `hiddenCount` = collapsed ? countDescendants : 0

- [ ] **Step 1: 写失败测试**

```swift
@Test func branchToggle_onExpandedParent_showsPlusSemanticsFields() {
    var doc = MindMapDocument.blank()
    let child = Node(text: "子", side: .right, children: [Node(text: "孙")])
    doc.root.children = [child]
    let snap = RadialLayout.layout(document: doc, measure: TextMeasure())
    let toggles = snap.branchToggles.filter { $0.nodeId == child.id }
    #expect(toggles.count == 1)
    #expect(toggles[0].collapsed == false)
    #expect(toggles[0].side == .right)
    #expect(toggles[0].center.x > snap.frames[child.id]!.rect.maxX)
}

@Test func root_collapsed_stillHasLeftAndRightToggles() {
    var doc = MindMapDocument.blank()
    doc.root.children = [
        Node(text: "L", side: .left),
        Node(text: "R", side: .right),
    ]
    doc.root.collapsed = true
    let snap = RadialLayout.layout(document: doc, measure: TextMeasure())
    let sides = Set(snap.branchToggles.filter { $0.nodeId == doc.root.id }.map(\.side))
    #expect(sides == [.left, .right])
    #expect(snap.frames.count == 1)
}
```

将原依赖角标作为折叠主入口的断言改为：折叠节点出现在 `branchToggles` 且 `collapsed && hiddenCount >= 1`。`CollapseBadge.make` 测试可保留为「角标工厂返回 nil / 废弃」或改为不再调用（Task 5 停用绘制）。

- [ ] **Step 2: 跑测试确认失败**

Expected: `branchToggles` 不存在或为空。

- [ ] **Step 3: 实现生成逻辑**

在 `RadialLayout.layout` 末尾（及 root collapsed 早退路径）调用：

```swift
func appendToggles(for node: Node, frame: NodeFrame) {
    guard !node.children.isEmpty else { return }
    if frame.isRoot {
        let hasLeft = node.children.contains { $0.side == .left }
        let hasRight = node.children.contains { $0.side != .left }
        if node.collapsed || hasLeft {
            toggles.append(makeToggle(node: node, frame: frame, side: .left))
        }
        if node.collapsed || hasRight {
            toggles.append(makeToggle(node: node, frame: frame, side: .right))
        }
    } else if let side = frame.side {
        toggles.append(makeToggle(node: node, frame: frame, side: side))
    }
}

func makeToggle(node: Node, frame: NodeFrame, side: Side) -> BranchToggle {
    let dir: CGFloat = side == .left ? -1 : 1
    return BranchToggle(
        nodeId: node.id,
        side: side,
        center: CGPoint(
            x: frame.center.x + dir * (frame.size.width / 2 + LayoutConstants.branchToggleGap),
            y: frame.center.y
        ),
        collapsed: node.collapsed,
        hiddenCount: node.collapsed ? countDescendants(node) : 0
    )
}
```

对 `frames` 中每个 id 找树节点并 `appendToggles`（根折叠时 frames 仅根，仍处理根）。

- [ ] **Step 4: 跑测试确认通过**

Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Layout/ LinvaApp/LinvaAppTests/RadialLayoutTests.swift \
  LinvaApp/LinvaApp/Session/DocumentSession.swift \
  LinvaApp/LinvaAppTests/HitTestTests.swift
git commit -m "$(cat <<'EOF'
feat: Layout 产出分叉 BranchToggle

根折叠时仍保留左右折叠入口。
EOF
)"
```

---

### Task 5: Metal 分叉绘制 + 命中优先 + 停用角标

**Files:**
- Create: `LinvaApp/LinvaApp/Render/CanvasHitTesting.swift`（把 `hitTest` / 新逻辑移入，供测试）
- Modify: `LinvaApp/LinvaApp/Render/CanvasMetalView.swift`
- Modify: `LinvaApp/LinvaApp/Render/MetalRenderer.swift`
- Modify: `LinvaApp/LinvaAppTests/HitTestTests.swift`
- Modify: `LinvaApp/LinvaApp/ContentView.swift` — `onToggleCollapse: (UUID) -> Void`

**Interfaces:**
- Consumes: `LayoutSnapshot.branchToggles`
- Produces:

```swift
enum CanvasHit: Equatable {
    case branchToggle(nodeId: UUID)
    case node(UUID)
    case empty
}

func hitTestCanvas(
    screenPoint: CGPoint,
    snapshot: LayoutSnapshot,
    camera: Camera
) -> CanvasHit

// MetalRenderer.draw(..., selectedIds: Set<UUID>, selectionAnchorId: UUID?)
// 绘制顺序：边 → 填充 → 文字 → 分叉控件 → 多选描边（锚点可用虚线或双描边）
// CollapseBadge 绘制路径改为空操作或删除调用
```

分叉外观：圆形底 + 文字「＋」或「−\(N)」；折叠态用 accent 实心（对齐原型）。文字可复用 `TextAtlas`/`CollapseBadgeAtlas` 思路，新建小 atlas 或临时 `NSImage` 纹理。

点击 toggle：`commandBus.execute(.toggleCollapse(id: nodeId))`，**不改选中**。

- [ ] **Step 1: 写失败测试 — toggle 命中优先于节点**

```swift
@Test func hitTest_prefersBranchToggleOverNode() {
    let nodeId = UUID()
    let frame = NodeFrame(
        id: nodeId, text: "P", center: .zero,
        size: NodeSize(width: 80, height: 40),
        isRoot: false, side: .right,
        collapsed: false, hiddenCount: 0
    )
    let toggle = BranchToggle(
        nodeId: nodeId, side: .right,
        center: CGPoint(x: 58, y: 0),
        collapsed: false, hiddenCount: 0
    )
    let snapshot = LayoutSnapshot(
        frames: [nodeId: frame], edges: [], branchToggles: [toggle]
    )
    let hit = hitTestCanvas(
        screenPoint: CGPoint(x: 58, y: 0),
        snapshot: snapshot,
        camera: Camera()
    )
    #expect(hit == .branchToggle(nodeId: nodeId))
}
```

- [ ] **Step 2: 跑测试确认失败**

Expected: FAIL。

- [ ] **Step 3: 实现 hitTestCanvas + Metal 绘制 + mouseDown 分支**

```swift
func hitTestCanvas(...) -> CanvasHit {
    let world = camera.screenToWorld(screenPoint)
    if let toggle = snapshot.branchToggles.first(where: {
        let dx = world.x - $0.center.x
        let dy = world.y - $0.center.y
        return dx * dx + dy * dy <= LayoutConstants.branchToggleHitRadius
            * LayoutConstants.branchToggleHitRadius
    }) {
        return .branchToggle(nodeId: toggle.nodeId)
    }
    if let id = hitTestNode(...) { return .node(id) }
    return .empty
}
```

`mouseDown`：

```swift
switch hitTestCanvas(...) {
case .branchToggle(let id):
    onToggleCollapse(id)
    dragPanState.begin(at: point, onNode: true) // 抑制拖移
case .node(let id):
    onSelect(id) // Task 6 再改修饰键
    ...
case .empty:
    onSelect(nil) // Task 6 改为可能开始框选
    ...
}
```

`MetalRenderer.draw`：对每个 `BranchToggle` 画圆 + label；对 `selectedIds` 每个 frame 画描边；若 `id == selectionAnchorId && selectedIds.count > 1` 再画虚线或颜色区分（可用第二色 stroke）。

停用 `drawBadges` 调用（角标不再作为产品入口）。

- [ ] **Step 4: 跑测试 + 手测分叉**

Expected: HitTest PASS；运行 App：有子节点处可见 ＋，点击折叠后变 −N，后代隐藏。

- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Render/ LinvaApp/LinvaApp/ContentView.swift \
  LinvaApp/LinvaAppTests/HitTestTests.swift
git commit -m "$(cat <<'EOF'
feat: Metal 分叉折叠控件与优先命中

折叠入口迁画布；停用节点角标主路径。
EOF
)"
```

---

### Task 6: 框选、空格平移、修饰键选中与键盘

**Files:**
- Modify: `LinvaApp/LinvaApp/Render/CanvasMetalView.swift`（手势状态机；可选抽出 `CanvasPointerState`）
- Modify: `LinvaApp/LinvaApp/ContentView.swift`（回调带修饰键；Esc/⌘A/`/`/⌘.）
- Modify: `LinvaApp/LinvaApp/Render/MetalRenderer.swift` 或 Canvas 上画 marquee 矩形
- Create/Modify tests: `HitTestTests` 增加 `marqueeIntersectingIds` 纯函数测试

**Interfaces:**
- Consumes: Task 1–5
- Produces:

```swift
func marqueeIntersectingIds(
    worldRect: CGRect,
    snapshot: LayoutSnapshot
) -> Set<UUID>  // frames 的 rect 与 worldRect 相交

// CanvasMTKView 指针状态：
// enum: idle / pan(start) / marquee(start, additive)
// 空格：flagsChanged 跟踪 spaceHeld；或 keyDown/Up keyCode 49
// 框选松手：|w|<4 && |h|<4 → 点空白清空（非 additive）
// mouseDown 在 empty：若 spaceHeld || isOtherMouse → pan；否则 marquee
// 节点 click：event.modifierFlags — .command → toggle；.shift → range；否则 selectOnly
// 编辑态：session.editingId != nil 时忽略框选与多选手势（双击编辑除外已有）
```

ContentView 快捷键（画布 `keyDown` 或 `.onKeyPress`）：
- Esc → `clearSelection()`（非编辑）
- ⌘A → `replaceSelection(Set(snapshot.frames.keys), anchorId: …)`
- `/` 或 ⌘. → 批量 `setCollapsed`（Task 3 若未加命令则本任务补 `setCollapsed`）

若 Task 3 未含 `setCollapsed`，本任务一并加入：

```swift
case setCollapsed(ids: [UUID], collapsed: Bool)

// 语义：有任一展开 → 全部折；否则全部展
let targets = selectedIds.filter { model.node(id: $0)?.children.isEmpty == false }
let anyExpanded = targets.contains { model.node(id: $0)?.collapsed == false }
bus.execute(.setCollapsed(ids: targets, collapsed: anyExpanded))
```

- [ ] **Step 1: 写失败测试 — 框选求交**

```swift
@Test func marqueeIntersectingIds_hitsOverlappingFramesOnly() {
    let a = UUID(); let b = UUID()
    let fa = NodeFrame(id: a, text: "A", center: CGPoint(x: 0, y: 0),
                       size: NodeSize(width: 20, height: 20),
                       isRoot: false, side: .right, collapsed: false, hiddenCount: 0)
    let fb = NodeFrame(id: b, text: "B", center: CGPoint(x: 100, y: 0),
                       size: NodeSize(width: 20, height: 20),
                       isRoot: false, side: .right, collapsed: false, hiddenCount: 0)
    let snap = LayoutSnapshot(frames: [a: fa, b: fb], edges: [], branchToggles: [])
    let ids = marqueeIntersectingIds(
        worldRect: CGRect(x: -5, y: -5, width: 30, height: 30),
        snapshot: snap
    )
    #expect(ids == [a])
}
```

- [ ] **Step 2: 跑测试确认失败**

Expected: FAIL。

- [ ] **Step 3: 实现求交 + 手势 + 快捷键 + setCollapsed**

实现要点：
- `CanvasDragPanState` 扩展或替换为含 `marqueeOrigin` / `marqueeCurrent` / `additive` / `isPanning`
- 拖动中更新 marquee，`setNeedsDisplay`；draw 时画半透明矩形（视图坐标）
- `mouseUp`：世界矩形求交 → `replaceSelection` 或 `selectedIds.union`
- `onSelect` 回调升级为携带 `NSEvent` 或 `(UUID?, modifiers)` — 推荐 ContentView 传入：

```swift
onCanvasClick: (CanvasHit, NSEvent) -> Void
```

ContentView 内根据 `editingId` 与修饰键分发。

- [ ] **Step 4: 跑全量相关测试并手测清单**

```bash
xcodebuild test -project LinvaApp/LinvaApp.xcodeproj -scheme LinvaApp \
  -destination 'platform=macOS' -only-testing:LinvaAppTests
```

手测（设计 §7.2）：
1. 框选 ≥3 节点 + ⌫  
2. 空格拖平移；默认拖框选  
3. ⌘ 点加减选；同父 Shift 连选；锚点可辨  
4. 分叉 ＋/−N  
5. 多选时 Tab/同级禁用  
6. Esc、⌘A、`/`  

Expected: 测试 PASS；手测通过。

- [ ] **Step 5: Commit**

```bash
git add LinvaApp/
git commit -m "$(cat <<'EOF'
feat: 框选、修饰键多选与批量折叠快捷键

默认空白拖框选，空格拖平移；对齐整理效率 PRD。
EOF
)"
```

---

## Spec Coverage（自检）

| Spec / FR | Task |
|-----------|------|
| FR-O1 单击单选 | 1, 6 |
| FR-O2 ⌘ 加减选 | 1, 6 |
| FR-O3 Shift 同父 | 1, 6 |
| FR-O4 框选 / 追加 / 阈值清空 | 6 |
| FR-O5 空格平移 | 6 |
| FR-O6 Esc、⌘A | 6 |
| FR-O7 严格工具条、已选 N、去折叠按钮 | 2 |
| FR-O8 批量删除 + Undo 一步 | 3 |
| FR-O9～O11 分叉位置/极性/语义 | 4, 5 |
| FR-O12 `/` · ⌘. | 6 |
| FR-O13 编辑排他 | 6 |
| 锚点虚线视觉 | 5–6 |
| 停用角标主入口 | 5 |

## Placeholder / 一致性自检

- 无 TBD；`primarySelectedId` 规则与 spec 一致（`uuidString` 最小）
- 框选阈值 4pt 与原型一致
- `LayoutSnapshot` 三字段在测试与 Session 空快照处统一
- `delete(ids:)` 与 `setCollapsed` 命名在 Task 3/6 交叉引用一致

---
