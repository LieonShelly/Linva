# Linva 搬枝（拖拽成子与剪贴板）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有 LinvaApp 上交付改层级：拖拽成子 + 应用内剪贴板（⌘C/⌘X/⌘V），行为对齐 PRD 与原型。

**Architecture:** 沿用 v1 分层。`MindMapModel` 增 `movableTopLevel`/`reparent`/`duplicate`/`attachChild`；`MindMapCommand` 增 `moveToParent`/`pasteAsChild`（各为命令栈一步）；`DocumentSession` 持剪贴板会话态与 `cutSourceIds`；`CanvasMTKView` 手势机扩为 `pendingDrag`/`drag`；`MetalRenderer` 画放置高亮与剪切源弱化；壳层加 ⌘C/X/V 与工具条剪切/复制/粘贴。

**Tech Stack:** Swift、SwiftUI、AppKit（NSEvent 修饰键）、MetalKit、Swift Testing；工程 `LinvaApp/`（`PBXFileSystemSynchronizedRootGroup`）。

**Spec:** `docs/superpowers/specs/2026-09-26-linva-move-reparent-clipboard-design.md`

## Global Constraints

- 平台：macOS（工程 `MACOSX_DEPLOYMENT_TARGET = 26.4`）
- 选中 / 相机 / **剪贴板** 均不入 `.linva`；文件格式 version 不变
- 剪贴板为**应用内会话态**：不入系统剪贴板、不入 Undo 栈（copy/cut 无树变更）；仅粘贴/搬移进命令栈
- 整节点任意位置松手=成子；上下边插同级完全留给「同级排序」PRD（本增量不做分区）
- 拖放/粘贴目标若折叠则展开；成功后选中**收敛到搬后/粘贴节点**
- 粘贴目标 = `primarySelectedId`（锚点优先）
- Model/Command **禁止** import SwiftUI / AppKit / Metal；仅 Foundation
- 文档中文优先；代码标识符英文
- 测试：`xcodebuild test -project LinvaApp/LinvaApp.xcodeproj -scheme LinvaApp -destination 'platform=macOS' -only-testing:LinvaAppTests/<Suite>`

---

## File Structure

```text
LinvaApp/LinvaApp/
  Model/MindMapModel.swift          # 改：movableTopLevel · reparent · duplicate · attachChild · isValidDropTarget · removeWithoutSelection
  Commands/MindMapCommand.swift     # 改：moveToParent · pasteAsChild
  Commands/CommandBus.swift         # 改：两个命令分支 + 选中收敛
  Session/Clipboard.swift           # 新建：ClipboardMode + ClipboardPayload
  Session/DocumentSession.swift     # 改：clipboard · cutSourceIds · copy/cut/paste/cancelCut/move · canCopy/canCut/canPaste
  Render/CanvasHitTesting.swift     # 改：hasExceededDragThreshold
  Render/CanvasMetalView.swift      # 改：pendingDrag/drag 手势 · move/copy/cut/paste/cancelCut 动作
  Render/MetalRenderer.swift        # 改：放置高亮 · 剪切源弱化
  ContentView.swift                 # 改：键盘与动作接线 · 粘贴目标
  App/MainToolbar.swift             # 改：剪切/复制/粘贴按钮

LinvaApp/LinvaAppTests/
  ModelTests.swift                  # 扩：movableTopLevel · duplicate · reparent · isValidDropTarget
  CommandBusTests.swift             # 扩：moveToParent · pasteAsChild
  DocumentSessionTests.swift        # 扩：copy/cut/cancel/paste
  CanvasInteractionTests.swift      # 扩：hasExceededDragThreshold
```

---

### Task 1: Model — movableTopLevel 与 duplicate

**Files:**
- Modify: `LinvaApp/LinvaApp/Model/MindMapModel.swift`
- Test: `LinvaApp/LinvaAppTests/ModelTests.swift`

**Interfaces:**
- Consumes: 现有树 API（`node(id:)` / `topLevelDeletableIds(from:)`）
- Produces:
  - `func movableTopLevel(ids: Set<UUID>) -> [UUID]` — 与 `topLevelDeletableIds` 同语义（排根 + 祖先去重）
  - `func duplicate(_ node: Node) -> Node` — 深拷贝子树并递归换新 UUID

- [ ] **Step 1: 写失败测试**

在 `ModelTests.swift` 追加：

```swift
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
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -project LinvaApp/LinvaApp.xcodeproj -scheme LinvaApp -destination 'platform=macOS' -only-testing:LinvaAppTests/ModelTests`
Expected: FAIL（方法缺失 / 断言失败）。

- [ ] **Step 3: 实现**

在 `MindMapModel` 中追加：

```swift
/// 可搬顶层：排除中心主题，祖先已在集内则不再单列（语义与批量删除一致）。
func movableTopLevel(ids: Set<UUID>) -> [UUID] {
    topLevelDeletableIds(from: ids)
}

/// 深拷贝子树并递归换新 UUID（Node 为值类型，结构天然深拷贝，只需换 id）。
func duplicate(_ node: Node) -> Node {
    var copy = node
    copy.id = UUID()
    copy.children = node.children.map { duplicate($0) }
    return copy
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2。Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Model/MindMapModel.swift LinvaApp/LinvaAppTests/ModelTests.swift
git commit -m "$(cat <<'EOF'
feat: Model 可搬顶层与深拷贝

为拖拽/剪贴板提供 movableTopLevel 与 duplicate（换新 UUID）。
EOF
)"
```

---

### Task 2: Model — reparent 与放置守卫

**Files:**
- Modify: `LinvaApp/LinvaApp/Model/MindMapModel.swift`
- Test: `LinvaApp/LinvaAppTests/ModelTests.swift`

**Interfaces:**
- Consumes: Task 1 `movableTopLevel` / `duplicate`；现有 `removeWithoutChangingSelection`（private）、`pathTo`（private）、`node(id:)`、`nextSide`（private）、`mutate(id:_:)`（private）、`restoreChild`
- Produces:
  - `struct ReparentRecord: Equatable { let parentId: UUID; let index: Int; let node: Node }`
  - `func reparent(ids: [UUID], to targetId: UUID) -> [ReparentRecord]`
  - `func attachChild(_ node: Node, to parentId: UUID)`
  - `func removeWithoutSelection(id: UUID) -> (parentId: UUID, index: Int, node: Node)?`
  - `func isDescendant(_ nodeId: UUID, of ancestorId: UUID) -> Bool`
  - `func isValidDropTarget(_ target: UUID, movingIds: Set<UUID>) -> Bool`

- [ ] **Step 1: 写失败测试**

```swift
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
```

- [ ] **Step 2: 跑测试确认失败**

Run: `-only-testing:LinvaAppTests/ModelTests`。Expected: FAIL。

- [ ] **Step 3: 实现**

在 `MindMapModel` 中追加（`ReparentRecord` 放文件顶部、`final class` 外或内部均可，建议文件内顶层）：

```swift
struct ReparentRecord: Equatable {
    let parentId: UUID
    let index: Int
    let node: Node
}
```

```swift
/// 把可搬顶层整体搬到 targetId 下（末尾）；守卫 targetId 不为被搬节点自身/后代。
/// 目标为中心主题时按 v1「侧」均衡规则分配 left/right；成功后 target.collapsed = false。
@discardableResult
func reparent(ids: [UUID], to targetId: UUID) -> [ReparentRecord] {
    let moving = movableTopLevel(ids: Set(ids))
    guard !moving.isEmpty,
          node(id: targetId) != nil,
          !moving.contains(targetId),
          !moving.contains(where: { isDescendant(targetId, of: $0) }) else {
        return []
    }

    var records: [ReparentRecord] = []
    for id in moving {
        guard let path = pathTo(id),
              let oldParent = path.parentId,
              let node = node(id: id) else { continue }
        _ = removeWithoutChangingSelection(id: id)
        records.append(ReparentRecord(parentId: oldParent, index: path.index, node: node))
        attachChild(node, to: targetId)
    }
    _ = mutate(id: targetId) { $0.collapsed = false }
    return records
}

/// 把既有节点追加为 parentId 的子；目标为中心主题时自动分侧。不改选中。
func attachChild(_ node: Node, to parentId: UUID) {
    _ = mutate(id: parentId) { parent in
        var n = node
        if parentId == document.root.id { n.side = nextSide() }
        parent.children.append(n)
    }
}

/// 移除但不改选中（供粘贴 Undo 等）。
func removeWithoutSelection(id: UUID) -> (parentId: UUID, index: Int, node: Node)? {
    removeWithoutChangingSelection(id: id)
}

/// nodeId 是否在 ancestorId 的子树中（不含 ancestorId 自身）。
func isDescendant(_ nodeId: UUID, of ancestorId: UUID) -> Bool {
    guard nodeId != ancestorId,
          let ancestor = node(id: ancestorId) else { return false }
    return Self.find(id: nodeId, in: ancestor) != nil
}

/// 拖放/粘贴目标合法性：存在、不在被搬集内、不是任一被搬节点的后代。
func isValidDropTarget(_ target: UUID, movingIds: Set<UUID>) -> Bool {
    guard node(id: target) != nil, !movingIds.contains(target) else { return false }
    return !movingIds.contains { isDescendant(target, of: $0) }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2。Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Model/MindMapModel.swift LinvaApp/LinvaAppTests/ModelTests.swift
git commit -m "$(cat <<'EOF'
feat: Model reparent 与放置守卫

可搬顶层搬为子，守卫自身/后代/中心主题；贴根自动分侧并展开目标。
EOF
)"
```

---

### Task 3: Command — moveToParent 与 pasteAsChild

**Files:**
- Modify: `LinvaApp/LinvaApp/Commands/MindMapCommand.swift`
- Modify: `LinvaApp/LinvaApp/Commands/CommandBus.swift`
- Test: `LinvaApp/LinvaAppTests/CommandBusTests.swift`

**Interfaces:**
- Consumes: Task 1–2 Model API（`reparent` / `duplicate` / `attachChild` / `removeWithoutSelection` / `setCollapsed` / `replaceSelection`）
- Produces:
  - `MindMapCommand.moveToParent(ids: [UUID], parentId: UUID)`
  - `MindMapCommand.pasteAsChild(payload: [Node], parentId: UUID)`
  - 二者均：一步 Undo/Redo、选中收敛到受影响节点、目标折叠随命令展开/还原

- [ ] **Step 1: 写失败测试**

在 `CommandBusTests.swift` 追加：

```swift
@Test func moveToParent_undoRestoresPosition_andSelection() {
    let model = MindMapModel.makeNew()
    let bus = CommandBus(model: model)
    let root = model.document.root.id
    let a = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
    let b = model.insertChild(parentId: root, text: "B", side: .left, at: nil)
    bus.clearHistory()

    bus.execute(.moveToParent(ids: [a], parentId: b))
    #expect(model.node(id: b)?.children.map(\.id) == [a])
    #expect(Set(model.selectedIds) == [a])

    bus.undo()
    #expect(model.parentId(of: a) == root)
    #expect(Set(model.selectedIds) == [a])

    bus.redo()
    #expect(model.node(id: b)?.children.map(\.id) == [a])
}

@Test func pasteAsChild_undoRemovesCopies_redoReinsertsSameIds() {
    let model = MindMapModel.makeNew()
    let bus = CommandBus(model: model)
    let root = model.document.root.id
    let a = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
    let target = model.insertChild(parentId: root, text: "T", side: .left, at: nil)
    let src = model.node(id: a)!
    bus.clearHistory()

    bus.execute(.pasteAsChild(payload: [src], parentId: target))
    let pastedId = model.node(id: target)!.children[0].id
    #expect(model.node(id: target)?.children.count == 1)
    #expect(pastedId != a)
    #expect(Set(model.selectedIds) == [pastedId])

    bus.undo()
    #expect(model.node(id: target)?.children.isEmpty == true)
    #expect(model.node(id: pastedId) == nil)

    bus.redo()
    #expect(model.node(id: target)?.children.map(\.id) == [pastedId])
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `-only-testing:LinvaAppTests/CommandBusTests`。Expected: FAIL（case 缺失）。

- [ ] **Step 3: 实现**

`MindMapCommand.swift` 追加：

```swift
    case moveToParent(ids: [UUID], parentId: UUID)
    case pasteAsChild(payload: [Node], parentId: UUID)
```

`CommandBus.swift` 的 `applyForward` switch 追加两个分支：

```swift
        case let .moveToParent(ids, parentId):
            let priorCollapsed = model.node(id: parentId)?.collapsed
            let records = model.reparent(ids: ids, to: parentId)
            guard !records.isEmpty else { return nil }
            let movedIds = Set(records.map(\.node.id))
            let anchor = movedIds.min { $0.uuidString < $1.uuidString }
            model.replaceSelection(movedIds, anchorId: anchor)
            return Entry(
                undo: {
                    // 先从目标父移除被搬节点，再按原父/原下标恢复，避免节点同时存在于新旧两处。
                    for r in records.sorted(by: { $0.index < $1.index }) {
                        _ = self.model.removeWithoutSelection(id: r.node.id)
                        self.model.restoreChild(parentId: r.parentId, index: r.index, node: r.node)
                    }
                    if let priorCollapsed {
                        self.model.setCollapsed(id: parentId, to: priorCollapsed)
                    }
                    self.model.replaceSelection(movedIds, anchorId: anchor)
                },
                redo: {
                    _ = self.model.reparent(ids: ids, to: parentId)
                    self.model.replaceSelection(movedIds, anchorId: anchor)
                }
            )

        case let .pasteAsChild(payload, parentId):
            let priorSelection = model.selectedIds
            let priorAnchor = model.selectionAnchorId
            let priorCollapsed = model.node(id: parentId)?.collapsed
            var inserted: [Node] = []
            for node in payload {
                let copy = model.duplicate(node)
                model.attachChild(copy, to: parentId)
                inserted.append(copy)
            }
            guard !inserted.isEmpty else { return nil }
            let insertedIds = Set(inserted.map(\.id))
            let anchor = insertedIds.min { $0.uuidString < $1.uuidString }
            if model.node(id: parentId)?.collapsed == true {
                model.setCollapsed(id: parentId, to: false)
            }
            model.replaceSelection(insertedIds, anchorId: anchor)
            return Entry(
                undo: {
                    for n in inserted {
                        _ = self.model.removeWithoutSelection(id: n.id)
                    }
                    if let priorCollapsed {
                        self.model.setCollapsed(id: parentId, to: priorCollapsed)
                    }
                    self.model.replaceSelection(priorSelection, anchorId: priorAnchor)
                },
                redo: {
                    for n in inserted {
                        self.model.attachChild(n, to: parentId)
                    }
                    if model.node(id: parentId)?.collapsed == true {
                        self.model.setCollapsed(id: parentId, to: false)
                    }
                    self.model.replaceSelection(insertedIds, anchorId: anchor)
                }
            )
```

- [ ] **Step 4: 跑测试确认通过**

Run: `-only-testing:LinvaAppTests/CommandBusTests` 与 `-only-testing:LinvaAppTests/ModelTests`。Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Commands/MindMapCommand.swift LinvaApp/LinvaApp/Commands/CommandBus.swift LinvaApp/LinvaAppTests/CommandBusTests.swift
git commit -m "$(cat <<'EOF'
feat: moveToParent 与 pasteAsChild 命令

剪贴板/拖拽共用的搬移与复制粘贴，各一步 Undo；目标折叠随命令展开。
EOF
)"
```

---

### Task 4: Session — 剪贴板态与操作

**Files:**
- Create: `LinvaApp/LinvaApp/Session/Clipboard.swift`
- Modify: `LinvaApp/LinvaApp/Session/DocumentSession.swift`
- Test: `LinvaApp/LinvaAppTests/DocumentSessionTests.swift`

**Interfaces:**
- Consumes: Task 1–3（`movableTopLevel` / `isValidDropTarget` / 命令）
- Produces:
  - `enum ClipboardMode: Equatable { case copy, cut }`
  - `struct ClipboardPayload: Equatable { let mode: ClipboardMode; let nodes: [Node]; let sourceIds: [UUID] }`
  - Session：`@Published clipboard`、`@Published cutSourceIds`、`copySelection()`、`cutSelection()`、`pasteToPrimary()`、`cancelCut()`、`move(_:to:)`、`canCopy`、`canCut`、`canPaste`

- [ ] **Step 1: 写失败测试**

新建 `LinvaApp/LinvaAppTests/ClipboardTests.swift`（或追加到 `DocumentSessionTests.swift`，二选一；推荐新建独立 Suite）：

```swift
import Foundation
import Testing
@testable import LinvaApp

@Suite("Clipboard")
struct ClipboardTests {
    @Test func cut_thenCancel_leavesTreeUntouched() {
        let session = DocumentSession()
        let root = session.model.document.root.id
        let a = session.model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        session.selectOnly(a)

        session.cutSelection()
        #expect(session.cutSourceIds == [a])
        #expect(session.model.node(id: a) != nil)

        session.cancelCut()
        #expect(session.clipboard == nil)
        #expect(session.cutSourceIds.isEmpty)
        #expect(session.model.node(id: a) != nil)
    }

    @Test func copy_thenTwoPastes_eachIndependent() {
        let session = DocumentSession()
        let root = session.model.document.root.id
        let a = session.model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        let t1 = session.model.insertChild(parentId: root, text: "T1", side: .left, at: nil)
        let t2 = session.model.insertChild(parentId: root, text: "T2", side: .left, at: nil)
        session.selectOnly(a)
        session.copySelection()
        session.selectOnly(t1)
        session.pasteToPrimary()
        session.selectOnly(t2)
        session.pasteToPrimary()

        #expect(session.model.node(id: t1)?.children.count == 1)
        #expect(session.model.node(id: t2)?.children.count == 1)
        #expect(session.model.node(id: t1)?.children[0].id
            != session.model.node(id: t2)?.children[0].id)
        #expect(session.model.node(id: a) != nil)
    }

    @Test func pasteToOwnDescendant_isNoOp_forCut() {
        let session = DocumentSession()
        let root = session.model.document.root.id
        let a = session.model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        let g = session.model.insertChild(parentId: a, text: "G", side: nil, at: nil)
        session.selectOnly(a)
        session.cutSelection()
        session.selectOnly(g)
        session.pasteToPrimary()

        #expect(session.model.node(id: a) != nil)
        #expect(session.model.parentId(of: a) == root)  // 未搬
        #expect(session.cutSourceIds == [a])                          // 剪切态未清
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `-only-testing:LinvaAppTests/ClipboardTests`。Expected: FAIL（符号缺失）。

- [ ] **Step 3: 实现**

`LinvaApp/LinvaApp/Session/Clipboard.swift`：

```swift
import Foundation

enum ClipboardMode: Equatable {
    case copy
    case cut
}

struct ClipboardPayload: Equatable {
    let mode: ClipboardMode
    let nodes: [Node]      // 深拷贝快照
    let sourceIds: [UUID]  // cut 模式：源 ID
}
```

`DocumentSession.swift` 追加字段与方法：

```swift
    @Published private(set) var clipboard: ClipboardPayload?
    @Published private(set) var cutSourceIds: Set<UUID> = []

    func copySelection() {
        let tops = model.movableTopLevel(ids: model.selectedIds)
        guard !tops.isEmpty else { return }
        clipboard = ClipboardPayload(
            mode: .copy,
            nodes: tops.compactMap { model.node(id: $0) },
            sourceIds: []
        )
    }

    func cutSelection() {
        let tops = model.movableTopLevel(ids: model.selectedIds)
        guard !tops.isEmpty else { return }
        clipboard = ClipboardPayload(
            mode: .cut,
            nodes: tops.compactMap { model.node(id: $0) },
            sourceIds: tops
        )
        cutSourceIds = Set(tops)
    }

    func cancelCut() {
        clipboard = nil
        cutSourceIds = []
    }

    func pasteToPrimary() {
        guard let clipboard, let target = primarySelectedId else { return }
        switch clipboard.mode {
        case .copy:
            guard model.node(id: target) != nil else { return }
            commandBus.execute(.pasteAsChild(payload: clipboard.nodes, parentId: target))
        case .cut:
            let alive = clipboard.sourceIds.filter { model.node(id: $0) != nil }
            guard !alive.isEmpty,
                  model.isValidDropTarget(target, movingIds: Set(alive)) else { return }
            commandBus.execute(.moveToParent(ids: alive, parentId: target))
            cancelCut()
        }
    }

    func move(_ ids: [UUID], to targetId: UUID) {
        guard model.isValidDropTarget(targetId, movingIds: Set(ids)) else { return }
        commandBus.execute(.moveToParent(ids: ids, parentId: targetId))
    }

    var canCopy: Bool { !model.movableTopLevel(ids: model.selectedIds).isEmpty }
    var canCut: Bool { canCopy }

    var canPaste: Bool {
        guard let clipboard, let target = primarySelectedId else { return false }
        switch clipboard.mode {
        case .copy:
            return model.node(id: target) != nil
        case .cut:
            let alive = clipboard.sourceIds.filter { model.node(id: $0) != nil }
            return !alive.isEmpty && model.isValidDropTarget(target, movingIds: Set(alive))
        }
    }
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2。Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Session/Clipboard.swift LinvaApp/LinvaApp/Session/DocumentSession.swift LinvaApp/LinvaAppTests/ClipboardTests.swift
git commit -m "$(cat <<'EOF'
feat: Session 剪贴板态与操作

copy/cut/paste/cancel 与 canPaste；cut 不改树，粘贴才搬，成功后清态。
EOF
)"
```

---

### Task 5: Canvas — 拖拽手势

**Files:**
- Modify: `LinvaApp/LinvaApp/Render/CanvasHitTesting.swift`
- Modify: `LinvaApp/LinvaApp/Render/CanvasMetalView.swift`
- Test: `LinvaApp/LinvaAppTests/CanvasInteractionTests.swift`

**Interfaces:**
- Consumes: Task 2 `isValidDropTarget`、Task 4 `session.move(_:to:)`、`session.model.movableTopLevel`
- Produces:
  - `func hasExceededDragThreshold(from: CGPoint, to: CGPoint) -> Bool`
  - `CanvasPointerGesture.pendingDrag(origin: CGPoint, nodeId: UUID, movingIds: Set<UUID>)`
  - `CanvasPointerGesture.drag(movingIds: Set<UUID>, dropTarget: UUID?, lastPoint: CGPoint)`
  - `CanvasActions` 增 `move: ([UUID], UUID) -> Void`、`copy/cut/paste/cancelCut: () -> Void`
  - `CanvasMTKView` 计算属性 `currentDropTargetId: UUID?`

- [ ] **Step 1: 写失败测试**

在 `CanvasInteractionTests.swift` 追加：

```swift
@Test func hasExceededDragThreshold_crossesAtFourPoints() {
    let origin = CGPoint(x: 100, y: 100)
    #expect(!hasExceededDragThreshold(from: origin, to: CGPoint(x: 103, y: 101)))
    #expect(hasExceededDragThreshold(from: origin, to: CGPoint(x: 105, y: 100)))
    #expect(hasExceededDragThreshold(from: origin, to: CGPoint(x: 100, y: 96)))
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `-only-testing:LinvaAppTests/CanvasInteractionTests`. Expected: FAIL（函数缺失）。

- [ ] **Step 3: 实现**

`CanvasHitTesting.swift` 追加：

```swift
/// 位移超过拖拽阈值（与框选阈值一致的 4pt）才进入搬枝拖拽。
func hasExceededDragThreshold(from origin: CGPoint, to current: CGPoint) -> Bool {
    !isClickLike(marqueeRect(from: origin, to: current))
}
```

`CanvasMetalView.swift`：

1. `CanvasPointerGesture` 增两 case：

```swift
    /// 节点按下未拖：`movingIds` 为待搬集；松手未拖则收成单选。
    case pendingDrag(origin: CGPoint, nodeId: UUID, movingIds: Set<UUID>)
    /// 搬枝拖拽中：`dropTarget` 为当前合法放置目标（nil=空白/非法）。
    case drag(movingIds: Set<UUID>, dropTarget: UUID?, lastPoint: CGPoint)

    var currentDropTargetId: UUID? {
        if case let .drag(_, dropTarget, _) = self { return dropTarget }
        return nil
    }
```

2. `CanvasActions` 增：

```swift
    var move: ([UUID], UUID) -> Void = { _, _ in }
    var copy: () -> Void = {}
    var cut: () -> Void = {}
    var paste: () -> Void = {}
    var cancelCut: () -> Void = {}
```

3. `beginPointerGesture` 的 `.node` 分支改为：

```swift
        case let .node(id):
            let intent = wasEditing ? .replace : selectIntent(for: event)
            if event.clickCount == 2 {
                actions.edit(id)
                gesture = .none
                return
            }
            guard !wasEditing, intent == .replace else {
                actions.select(id, intent)
                gesture = .none
                return
            }
            let isMulti = session.selectedIds.count > 1
            if isMulti, session.selectedIds.contains(id) {
                // 已在多选中：保留多选供拖整组；松手未拖再收成单选。
                let moving = session.model.movableTopLevel(ids: session.selectedIds)
                gesture = .pendingDrag(
                    origin: point,
                    nodeId: id,
                    movingIds: Set(moving)
                )
            } else {
                actions.select(id, .replace)
                gesture = .pendingDrag(origin: point, nodeId: id, movingIds: [id])
            }
```

4. `continuePointerGesture` 增加 pendingDrag/drag 分支：

```swift
        case let .pendingDrag(origin, _, movingIds):
            guard hasExceededDragThreshold(from: origin, to: point) else { return }
            gesture = .drag(
                movingIds: movingIds,
                dropTarget: computeDropTarget(at: point, movingIds: movingIds),
                lastPoint: point
            )
            setNeedsDisplay(bounds)
        case let .drag(movingIds, _, lastPoint):
            let target = computeDropTarget(at: point, movingIds: movingIds)
            gesture = .drag(movingIds: movingIds, dropTarget: target, lastPoint: point)
            setNeedsDisplay(bounds)
```

5. `endPointerGesture` 改为处理全部 case（保留原 marquee 逻辑）：

```swift
    private func endPointerGesture() {
        defer { gesture = .none }
        switch gesture {
        case .none, .pan:
            break
        case .pendingDrag(_, let nodeId, _):
            // 未拖出阈值：收成单击单选。
            actions.select(nodeId, .replace)
        case .drag(let movingIds, let dropTarget, _):
            if let dropTarget {
                actions.move(Array(movingIds), dropTarget)
            }
            // dropTarget == nil：取消搬移，树不变。
        case .marquee(let origin, let current, let additive, let tracking):
            let rect = marqueeRect(from: origin, to: current)
            if !tracking || isClickLike(rect) {
                if !additive {
                    actions.select(nil, .replace)
                }
                return
            }
            let ids = marqueeIntersectingIds(
                worldRect: worldRect(fromScreenRect: rect, camera: session.camera),
                snapshot: session.snapshot
            )
            actions.marqueeSelect(ids, additive)
        }
    }
```

6. 新增私有辅助：

```swift
    private func computeDropTarget(at point: CGPoint, movingIds: Set<UUID>) -> UUID? {
        guard case let .node(id) = hitTestCanvas(
            screenPoint: point,
            snapshot: session.snapshot,
            camera: session.camera
        ) else { return nil }
        return session.model.isValidDropTarget(id, movingIds: movingIds) ? id : nil
    }
```

7. `draw(in:)` 传入放置目标：

```swift
    func draw(in view: MTKView) {
        renderer?.draw(
            in: view,
            snapshot: session.snapshot,
            camera: session.camera,
            selectedIds: session.selectedIds,
            selectionAnchorId: session.selectionAnchorId,
            cutSourceIds: session.cutSourceIds,
            dropTargetId: gesture.currentDropTargetId,
            marquee: gesture.marqueeScreenRect
        )
    }
```

（第 7 步依赖 Task 6 的 draw 签名；若本任务先跑，可先把 draw 调用改为占位传递 `cutSourceIds: session.cutSourceIds, dropTargetId: gesture.currentDropTargetId`，Task 6 补齐签名。）

- [ ] **Step 4: 跑测试确认通过**

Run: `-only-testing:LinvaAppTests/CanvasInteractionTests`。Expected: PASS（Task 6 未完成前可能因 draw 签名编译失败——如失败，先跳到 Task 6 完成签名，再回来验证本任务）。

- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Render/CanvasHitTesting.swift LinvaApp/LinvaApp/Render/CanvasMetalView.swift LinvaApp/LinvaAppTests/CanvasInteractionTests.swift
git commit -m "$(cat <<'EOF'
feat: 画布拖拽成子手势

节点拖出阈值即进入搬枝；多选整组搬可搬顶层；未拖收成单选。
EOF
)"
```

---

### Task 6: Renderer — 放置高亮与剪切弱化

**Files:**
- Modify: `LinvaApp/LinvaApp/Render/MetalRenderer.swift`
- Test: 手测（渲染无可单元断言的可观察契约；本任务以编译 + 手测为准）

**Interfaces:**
- Consumes: Task 5 的 `draw` 调用点（`cutSourceIds` / `dropTargetId`）
- Produces: `draw(in:snapshot:camera:selectedIds:selectionAnchorId:cutSourceIds:dropTargetId:marquee:)` 新签名

- [ ] **Step 1: 改签名**

`MetalRenderer.draw` 参数改为：

```swift
    func draw(
        in view: MTKView,
        snapshot: LayoutSnapshot,
        camera: Camera,
        selectedIds: Set<UUID>,
        selectionAnchorId: UUID?,
        cutSourceIds: Set<UUID>,
        dropTargetId: UUID?,
        marquee: CGRect?
    ) {
```

- [ ] **Step 2: 在 `draw` 主体、`drawSelectionStrokes` 之后追加两个绘制**

```swift
        drawCutWeaken(
            snapshot: snapshot,
            camera: camera,
            cutSourceIds: cutSourceIds,
            encoder: encoder,
            viewport: &viewport
        )
        drawDropHighlight(
            snapshot: snapshot,
            camera: camera,
            dropTargetId: dropTargetId,
            encoder: encoder,
            viewport: &viewport
        )
```

- [ ] **Step 3: 实现两个私有绘制**

```swift
    /// 剪切源弱化：半透明遮罩 + 虚线边框（对齐原型弱化/虚线）。
    private func drawCutWeaken(
        snapshot: LayoutSnapshot,
        camera: Camera,
        cutSourceIds: Set<UUID>,
        encoder: MTLRenderCommandEncoder,
        viewport: inout ViewportUniforms
    ) {
        guard !cutSourceIds.isEmpty else { return }
        let fillColor = rgba(NSColor.windowBackgroundColor.withAlphaComponent(0.55))
        let dashColor = rgba(.tertiaryLabelColor)
        let thickness = max(1.5, 2 * camera.scale)
        var vertices: [SolidVertex] = []
        for id in cutSourceIds {
            guard let frame = snapshot.frames[id] else { continue }
            let rect = screenRect(frame.rect, camera: camera)
            vertices += rectangleQuad(rect: rect, color: fillColor)
            vertices += dashedStrokeVertices(
                rect: rect.insetBy(dx: -3, dy: -3),
                thickness: thickness,
                dash: 5 * camera.scale,
                gap: 3 * camera.scale,
                color: dashColor
            )
        }
        drawSolid(vertices, encoder: encoder, viewport: &viewport)
    }

    /// 放置目标高亮：强调色加粗描边。
    private func drawDropHighlight(
        snapshot: LayoutSnapshot,
        camera: Camera,
        dropTargetId: UUID?,
        encoder: MTLRenderCommandEncoder,
        viewport: inout ViewportUniforms
    ) {
        guard let dropTargetId,
              let frame = snapshot.frames[dropTargetId] else { return }
        let rect = screenRect(frame.rect, camera: camera).insetBy(dx: -3, dy: -3)
        let vertices = strokeVertices(
            rect: rect,
            thickness: max(2.5, 3 * camera.scale),
            color: rgba(.controlAccentColor)
        )
        drawSolid(vertices, encoder: encoder, viewport: &viewport)
    }
```

- [ ] **Step 4: 编译 + 手测**

编译：`xcodebuild -project LinvaApp/LinvaApp.xcodeproj -scheme LinvaApp -configuration Debug -destination 'platform=macOS' build`。Expected: BUILD SUCCEEDED。
手测：运行 App，⌘X 后源节点呈弱化虚线；拖拽节点到合法目标出现强调色描边。

- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Render/MetalRenderer.swift
git commit -m "$(cat <<'EOF'
feat: 渲染放置高亮与剪切源弱化
EOF
)"
```

---

### Task 7: 壳层 — 快捷键与工具条

**Files:**
- Modify: `LinvaApp/LinvaApp/ContentView.swift`
- Modify: `LinvaApp/LinvaApp/App/MainToolbar.swift`
- Modify: `LinvaApp/LinvaApp/Render/CanvasMetalView.swift`（Esc 与 ⌘C/X/V 键位）

**Interfaces:**
- Consumes: Task 4 Session 操作、Task 5 `CanvasActions` 新动作
- Produces: 工具条剪切/复制/粘贴；⌘C/⌘X/⌘V/Esc 接线

- [ ] **Step 1: ContentView 动作**

在 `ContentView` 追加处理（均先 `commitEditing()` 再执行）：

```swift
    private func move(_ ids: [UUID], to targetId: UUID) {
        if session.editingId != nil { commitEditing() }
        session.move(ids, to: targetId)
    }

    private func copySelection() {
        if session.editingId != nil { commitEditing() }
        session.copySelection()
    }

    private func cutSelection() {
        if session.editingId != nil { commitEditing() }
        session.cutSelection()
    }

    private func paste() {
        if session.editingId != nil { commitEditing() }
        session.pasteToPrimary()
    }

    private func cancelCut() {
        session.cancelCut()
    }
```

把 `CanvasActions` 构造补上 `move: move, copy: copySelection, cut: cutSelection, paste: paste, cancelCut: cancelCut`。

- [ ] **Step 2: 快捷键（CanvasMTKView.keyDown）**

命令修饰分支补 `c`/`x`/`v`：

```swift
            switch key {
            case "c": actions.copy(); return
            case "x": actions.cut(); return
            case "v": actions.paste(); return
            case "a": actions.selectAll(); return
            case ".": actions.toggleCollapseSelection(); return
            default: break
            }
```

Esc 分支（`case 53`）改为：

```swift
        case 53:
            if !session.cutSourceIds.isEmpty {
                actions.cancelCut()
            } else {
                actions.select(nil, .replace)
            }
```

- [ ] **Step 3: MainToolbar**

`MainToolbar` 增字段 `canCut`/`canCopy`/`canPaste` 与 `cut`/`copy`/`paste` 闭包，并在「删除」后追加三按钮：

```swift
            Button(action: cut) {
                Label("剪切", systemImage: "scissors")
            }
            .disabled(!canCut)
            .help("剪切主题（⌘X）")

            Button(action: copy) {
                Label("复制", systemImage: "doc.on.doc")
            }
            .disabled(!canCopy)
            .help("复制主题（⌘C）")

            Button(action: paste) {
                Label("粘贴", systemImage: "doc.on.clipboard")
            }
            .disabled(!canPaste)
            .help("粘贴为主题子节点（⌘V）")
```

`ContentView` 的 `MainToolbar(...)` 调用补：

```swift
                    canCut: session.canCut,
                    canCopy: session.canCopy,
                    canPaste: session.canPaste,
                    cut: cutSelection,
                    copy: copySelection,
                    paste: paste,
```

- [ ] **Step 4: 全量测试 + 手测**

Run: `xcodebuild test -project LinvaApp/LinvaApp.xcodeproj -scheme LinvaApp -destination 'platform=macOS' -only-testing:LinvaAppTests`。Expected: TEST SUCCEEDED。

手测（PRD §6 验收表）：
1. 单节点拖到另一节点 → 成为其子
2. 多选拖到目标 → 仅可搬顶层搬过去，选中在搬后节点
3. 拖到自身子树 → 不搬
4. ⌘X → 选目标 → ⌘V → 源搬走，剪切态消失
5. ⌘C → 两处 ⌘V → 两处各有副本，源仍在
6. 剪切后 Esc → 树不变，弱化消失
7. 贴到中心主题 → 自动分侧

- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/ContentView.swift LinvaApp/LinvaApp/App/MainToolbar.swift LinvaApp/LinvaApp/Render/CanvasMetalView.swift
git commit -m "$(cat <<'EOF'
feat: 剪贴板快捷键与工具条按钮

⌘C/⌘X/⌘V 与剪切/复制/粘贴按钮；Esc 优先取消剪切态。
EOF
)"
```

---

## Spec Coverage（自检）

| Spec / FR | Task |
|-----------|------|
| FR-M1 拖动手势（阈值、修饰不拖） | 5 |
| FR-M2 多选整组拖 | 5 |
| FR-M3 放置高亮与成子、折叠展开 | 2, 3, 6 |
| FR-M4 非法放置（自身/后代/空白） | 2, 5 |
| FR-M5 贴中心主题分侧 | 2 |
| FR-M6 复制 ⌘C | 4, 7 |
| FR-M7 剪切 ⌘X、Esc 取消 | 4, 6, 7 |
| FR-M8 粘贴成子、非法目标 no-op | 3, 4 |
| FR-M9 工具条剪切/复制/粘贴 | 7 |
| FR-M10 同级排序范围（整节点成子） | Global（不做分区） |
| FR-M11 与删除/折叠共存 | 5（节点拖=搬枝，空白拖=框选） |
| Undo 粒度（move/paste 各一步） | 3 |

## 一致性自检

- `moveToParent` 与 `pasteAsChild` 均在 Task 3 定义，Task 4 Session 直接引用，命名一致。
- `attachChild` / `removeWithoutSelection` / `isValidDropTarget` / `movableTopLevel` 由 Task 1–2 定义，Task 3–5 消费，签名一致。
- `draw(...)` 新签名在 Task 5 调用点与 Task 6 定义处一致（cutSourceIds / dropTargetId 顺序一致）。
- `CanvasActions` 新动作（move/copy/cut/paste/cancelCut）在 Task 5 定义、Task 7 接线，命名一致。
- `hasExceededDragThreshold` 在 Task 5 定义并测试，复用既有 4pt 阈值，无重复常量。
