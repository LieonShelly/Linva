---
name: linva-command
description: 如何在 Linva 中新增一个可逆命令（MindMapCommand + CommandBus）。当需要添加或修改任何改变树结构的用户操作（增删改折叠、搬移、改侧、粘贴等）时使用。
license: proprietary
---

# Linva 命令扩展（CommandBus 模式）

给 Linva 加一个新的可逆命令时，按本技能走。命令是 Linva 唯一合法的「改树」入口；绕过命令栈直接改 `model` 会让 Undo 栈失真。

## 关键文件

- `Commands/MindMapCommand.swift` —— 命令的 enum 定义（`enum MindMapCommand: Equatable`）
- `Commands/CommandBus.swift` —— 命令执行与 undo/redo 栈
- `Model/MindMapModel.swift` —— 真正的树变更与快照记录
- `Session/DocumentSession.swift` —— 门面：把 UI 用例收敛成 `session.move(...)` 等方法，再 `commandBus.execute(...)`

## 铁律（违反会破坏 Undo）

1. **改树必走命令**：凡是会改变 `MindMapDocument` 的操作，必须 `commandBus.execute(某个 MindMapCommand)`，并让 `applyForward` 返回一个携带 undo/redo 闭包的 `Entry`。
2. **不入命令栈的例外**（这些不改变文档、只改会话态，**不要**套命令）：
   - 相机平移 / 缩放 / 适应画布（只改 `DocumentSession.camera`）
   - 选中 / 选中锚点（`model.selectOnly` / `replaceSelection` 等，直接改 model 的选中态）
   - 编辑草稿 / 搜索态（`draftText`、`search`）——不入 `.linva` 也不入栈
3. **Undo 必须精确还原**：undo 闭包要把树恢复到执行前的精确状态。若命令涉及「移动/删除节点」，undo 里用 `model.removeWithoutSelection(id:)` 先从目标父移除、再 `restoreChild(parentId:index:node:)` 按原父/原下标恢复，避免节点同时存在于新旧两处。
4. **捕获折叠态须在执行前**：任何会清空源父的命令，源父折叠态会被 `removeWithoutChangingSelection` 强置展开。undo 前必须用 `sourceParentCollapsed(for:)` 捕获原始折叠态，undo 时还原。
5. **无效/无变化 → 返回 nil 不入栈**：`applyForward` 对 no-op 应返回 `nil`（例：`setCollapsed` 目标值已一致、`toggleCollapse` 无子节点）。参考 `applyForward` 里各分支的 `guard ... else { return nil }`。
6. **多选命令需更新选中态**：批量操作（delete/move/insertSiblings/setSide）执行后 `model.replaceSelection(movedIds, anchorId:)`，undo 里恢复。

## 加一个命令的步骤

1. **加 enum case**（`MindMapCommand.swift`）。参数要能唯一定义「做什么」。Equatable 由编译器合成。
2. **在 `CommandBus.applyForward` 的 switch 加分支**：
   - 调用 model 的变更方法，拿到「撤销所需信息」（被删节点、旧折叠值、旧 side 等）；
   - `guard` 无效场景返回 `nil`；
   - 返回 `Entry(undo:redo:)`，两个闭包各自做精确还原/重做；
   - 若命令改选中，在闭包外先 `replaceSelection`，undo/redo 闭包里也恢复。
3. **在 `Model/MindMapModel.swift` 加变更方法**（纯 Foundation，不碰 UI/Metal）。方法应返回 undo 需要的数据结构，而不是 `Void`。
4. **在 `Session/DocumentSession.swift` 加用例方法**（`func xxx(...)`），内部 `commandBus.execute(...)`，让 View 只绑事件、不直接碰 CommandBus。
5. **写单测**（`LinvaAppTests/CommandBusTests.swift` 等）：测「执行 → undo → 状态还原 → redo → 状态再现」，重点覆盖折叠态与多选锚点。

## 现有命令清单（新增前先看是否已存在）

`addChild`、`addSibling`、`delete(ids:)`、`setBlocks(id:old:new:)`、`toggleCollapse`、`setCollapsed(ids:collapsed:)`、`moveToParent(ids:parentId:)`、`insertSiblings(ids:anchorId:position:)`、`setSide(ids:side:)`、`applyRootSide(ids:side:)`、`pasteAsChild(payload:parentId:)`、`setFill(ids:fill:)`（设置节点填色，`fill: NodeFill?`，`nil` 恢复无填色）、`setLayout(kind: LayoutKind)`（切换文档布局 `.radial`/`.logic`，文档属性命令，no-op 不入栈，仿 `setFill`）。

## 验证

改完跑 `xcodebuild test`（或 `CommandBusTests` 相关用例）。确认新增命令有「undo 后模型 == 执行前模型」的单测覆盖。
