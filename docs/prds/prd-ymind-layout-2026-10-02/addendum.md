# Addendum：新增布局类型 — 实现侧细节（不进 PRD 主线）

**所属 PRD：** `docs/prds/prd-ymind-layout-2026-10-02/prd.md`
**日期：** 2026-10-02
**读者：** 开发 Agent / 方案设计（specs → plans）；先读 PRD §4 FR-L1…L5 与 §6 验收要点。

> 涉及技能：`ymind-codec-version`（Codec v5 迁移）、`ymind-layout-snapshot`（布局算法 / NodeFrame / 接缝）、`ymind-command`（setLayout 命令）、`ymind-render-text`（逻辑图文字纹理复用，无新渲染）。开发前读对应 skill。

---

## 1. LayoutKind 与 Codec v5（FR-L1 细则）

- **字段**：`MindMapDocument` 增 `layout: LayoutKind`；`enum LayoutKind: String, Codable, Sendable, Equatable { case radial, logic }`，缺省 `.radial`。Codable 内建字符串编码，无需自定义。
- **版本升迁**：`MindMapDocument.currentVersion = 4 → 5`。`YMindCodec` decode 时：`version <= 4` → 升 5，`layout` 缺省 `.radial`（与 `fill`/`image` 缺省容错同一模式：Node 解码器对缺失字段天然容忍）。
- **历史链**：v1→v2、v2→v3、v3→v4（image 字段，v4 = 当前 main）已存在；v4→v5 在末尾追加，**不重写既有迁移**。
- **sanitize**：不变。布局不改节点约束；`side` 消毒规则（深层 side 清除）保持原样——切回辐射时左右分组依赖 `Node.side`，**不得因布局切换清 side**。
- **DocumentSession**：`@Published private(set) var layout: LayoutKind`（或读取 `model.document.layout`）；`relayout()` 按 layout 分派（见 §3）。

## 2. LogicLayout 排布算法（FR-L2 细则）

新文件 `YMindApp/Layout/LogicLayout.swift`，结构与 `RadialLayout` 同构（`subtreeHeight` 测高 → `placeBranch` 排布）：

```
根在最左（x = rootPad），rootFrame.isRoot = true, side = nil
每一层：child 垂直排列在 parent 右侧
  childX = parent.right + hGap
  childY = 该层 children 垂直居中（复用 vGap 堆叠）
递归展开子层
```

- **复用**：`TextMeasure.measure`、`centeredBlocks`（文本块撑满节点宽 / 图片块居中）、`collectPayloads`（图片节点 `imagePayloads`）——直接从 `RadialLayout` 提取为共享 static，或 LogicLayout 复制同构实现（实现时定，推荐提取避免双份）。
- **side 语义**：逻辑图 `NodeFrame.side` 统一 `.right`（方向常量用「向右」）；`EdgeGeometry.side` 同理。模型层 `Node.side` 不动。
- **边几何**：L 形正交——`M start → (controlX=to.x, from.y) → to`，即先水平到子节点 x 再垂直落到子 y；区别于辐射的对称双贝塞尔。可新增 `LogicLayout.orthogonalEdge(from:to:)`。
- **折叠 toggle**：`BranchToggle` 统一在节点右侧（`side = .right` 的 toggle 生成逻辑复用）；折叠行为与辐射一致（后代不占空间）。
- **根折叠退化**：`document.root.collapsed` 时输出与辐射一致的退化快照（仅 root frame + 无子边）。
- **间距**：复用 `LayoutConstants.hGap/vGap`（56/16），视觉过密再调（开放问题 9.3）。

## 3. setLayout 命令与 relayout 单点（FR-L3 细则）

- **命令**：`MindMapCommand` 增 `case setLayout(kind: LayoutKind)`。执行：
  - `DocumentSession.setLayout(_ kind:)`：`commitEditingIfNeeded()` → `commandBus.execute(.setLayout(kind: kind))`。
  - 命令 apply：`model.document.layout = kind`（或 `MindMapModel.setLayout` 返回旧值供 Undo）→ 触发 `relayout()`；undo/redo 反向重排。
  - no-op 不入栈（kind 相同跳过）；不改选中态（与 `setFill` 同模式）。
- **relayout 分派**（`DocumentSession.swift:295` 现状 `snapshot = RadialLayout.layout(...)`）：
  ```swift
  func relayout() {
      switch model.document.layout {
      case .radial: snapshot = RadialLayout.layout(document: model.document, measure: measure)
      case .logic:  snapshot = LogicLayout.layout(document: model.document, measure: measure)
      }
  }
  ```
  **所有**现有 `relayout()` 调用点（新文档/导入/命令后/撤销后）自动生效，无二处修改。
- **相机**：切换后不主动重设相机；`fitContent` 仅在首绘触发。若用户期望「切换即适配」，可让 `setLayout` 后 `markNeedsFitContent()`（实现时定，默认不重设相机，开放问题可加）。
- **工具栏**：`MainToolbar` 增「布局」分段/菜单（辐射 / 逻辑图），当前布局高亮；回调 → `session.setLayout`。

## 4. side 降级（FR-L4 细则）

- **UI 层**：`ContentView` 的 `canSetSide` 计算加 `layout != .logic` 条件；`MainToolbar` 侧向按钮（左/右）与侧向拖放意图在逻辑图下禁用/不响应。
- **命令层**：`setSide`/`applyRootSide` **不加新约束**（避免破坏 Undo 历史里旧 side 操作的回放）。
- **拖拽搬移**：`move` / 插入线 / 插入兄弟不受布局影响（父子关系不变）；仅「拖到根左侧/右侧设 side」手势在逻辑图下不生效。
- **切回辐射**：`Node.side` 数据完整保留，左右分组恢复。

## 5. 导出（FR-L5 细则）

- **PNG**：`PNGExporter` 走 `MetalRenderer.draw` 当前 `session.snapshot`——`relayout()` 产出哪张快照渲染哪张，自动按当前布局，零改动。
- **Markdown**：既有 FR-E2 遍历树输出结构，不读 layout，零改动。
- **.ymind**：FR-L1 持久化。

## 6. 测试建议

- **Model/Codec**：v5 往返（radial/logic）、v4 老文件打开（缺省 radial 零拒绝）、v1–v4 迁移链不破坏。
- **Layout**：`LogicLayoutTests`（新）——总分树帧位置（根最左、层右移）、L 形边端点、折叠 toggle 位置、根折叠退化、图片节点 collectPayloads、长文本宽度自适应不重叠。
- **命令**：`setLayout` 入栈/undo/redo 往返重排、no-op 不入栈、不改选中。
- **交互**：逻辑图下 setSide 禁用（UI）、拖拽搬移/插入线照常、切回辐射 side 恢复。
- **导出**：PNG 按当前布局渲染（真 Metal）。
- **边界**：`check-boundaries.sh` 全绿（不新增 import；LogicLayout 用 CoreGraphics/Foundation，白名单已覆盖）。

## 7. 分层/边界清单

| 关注点 | 处理 |
|--------|------|
| Render | **零改动**：只消费 `LayoutSnapshot`（架构已验证，见 PRD §4.2 与机会卡片 §架构约束） |
| HitTest/选中/折叠 | 基于 `NodeFrame`，自动兼容，零改动 |
| `check-boundaries.sh` | 不新增 import；新文件 `LogicLayout.swift` 在 Layout/ 层 |
| Codec | v5 独占升迁；v4 及以下缺省容错 |
| 与 1.0 并行开发（迁移闭环/图片） | 若 1.0 未合入：以 1.0 合并后 main 为基线开分支（机会卡片 §7 排期 A 即为此）；若先并行：接缝 = LayoutSnapshot / currentVersion 独占 |
