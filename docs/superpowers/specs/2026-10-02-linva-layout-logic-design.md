# Linva 设计文档：新增布局类型（逻辑图·总分树 + 布局切换器）

- 日期：2026-10-02
- 状态：已批准（2026-10-02，四节评审通过）
- 上游 PRD：[新增布局类型 PRD](../../prds/prd-linva-layout-2026-10-02/prd.md)（FR-L1…L5）
- 实现细则：[addendum](../../prds/prd-linva-layout-2026-10-02/addendum.md)
- 体验真源：`prototype/layout-switcher.html`
- 涉及技能：`linva-codec-version`、`linva-layout-snapshot`、`linva-command`

> 本文是 PRD + addendum 的实现落地版：PRD 定需求、addendum 定实现细节，本文记录评审拍板的设计决策与最终接缝，供 writing-plans 与实现引用。

---

## 1. 决策记录（评审拍板）

| # | 决策 | 结论 |
|---|------|------|
| D1 | 布局切换后相机行为 | **切换时自动 fit**（覆盖 PRD §4.3「相机保持」字面）：`setLayout` 后重置首绘适配，撤销/重做亦再适配。 |
| D2 | 工具栏「布局」入口形态 | **下拉菜单 `Picker(.menu)`**（辐射/逻辑图），当前布局标题可见。 |
| D3 | 布局引擎接缝 | `LayoutPipeline` 删引擎类型注入，改按 `document.layout` **分派**；`LayoutPipelineTests` 的 `FakeLayoutEngine` 用例改为分派用例。 |
| D4 | 共享辅助 | **提取 `LayoutSupport`**（测高/块/toggle/载荷共享），`RadialLayout` 瘦身；不双份复制。 |
| D5 | 逻辑图根位置 | 根**左缘贴 `LayoutConstants.rootPadX`**（左对齐，全图坐标恒非负），addendum「x = rootPad」取左缘解释。 |

沿用 addendum 已定假设：`⌥L` 循环切换；间距复用 `hGap/vGap`（56/16）；根折叠退化与辐射一致；`LayoutKind` 内建字符串 Codable。

---

## 2. 目标与非目标

- **目标**：同一棵树在「辐射」与「逻辑图（总分树）」间无损、瞬时切换；布局随 `.linva` 持久化；逻辑图下 side 操作降级置灰；PNG 按当前布局导出。
- **非目标**：主题/配色、多结构混用、切换动画、逻辑图上下侧语义、大纲视图（同 PRD §5）。

---

## 3. 架构与接缝（D3）

分层不变：`Model 变更 → Session.relayout() → LayoutPipeline → LayoutSnapshot → Render`。

- **`LayoutEngine` 协议不变**（`static layout(document:measure:)`），`RadialLayout` 与 `LogicLayout` 均 conform。
- **`LayoutPipeline.relayout(document:)`** 按 `document.layout` switch：
  ```swift
  switch document.layout {
  case .radial: return RadialLayout.layout(document: document, measure: measure)
  case .logic:  return LogicLayout.layout(document: document, measure: measure)
  }
  ```
  删除 `layoutEngineType` 注入（其「换引擎测试」职责被分派取代）。所有现有 `relayout()` 调用点（新建/导入/命令后/撤销后）自动生效。
- **Render/命中/选中/折叠零改动**：只消费 `LayoutSnapshot`（PRD §4.2 已验证假设）。
- **自动 fit（D1）**：`DocumentSession` 增 `@Published private(set) var fitVersion: Int` 与私有 `appliedLayoutForFit`；在统一收敛点 `markDirtyAndRelayout()`（每次命令变更都经此）末尾比较布局变化：
  ```swift
  if model.document.layout != appliedLayoutForFit {
      appliedLayoutForFit = model.document.layout
      fitVersion += 1
  }
  ```
  工具栏切换、⌘Z/⌘⇧Z 往返统一触发再适配。`CanvasMetalView.updateNSView` 观察 `fitVersion` 变化 → `markNeedsFitContent()` 重置首绘适配。

---

## 4. 布局引擎

### 4.1 `LayoutSupport`（D4，新文件 `Layout/LayoutSupport.swift`）
从 `RadialLayout` 提为共享 static（`BranchMetadata` 结构体一并外移）：
- `subtreeHeight(_:isRoot:measure:) -> BranchMetadata`
- `centeredBlocks(from:) -> [BlockLayoutFrame]`
- `countDescendants(_:) -> Int`
- `makeToggle(node:frame:side:) -> BranchToggle`
- `collectImagePayloads(root:frames:) -> [UUID: ImagePayload]`

`RadialLayout` 同步改用上述辅助，行为不变（`RadialLayoutTests`/`ImageLayoutTests` 兜底）。

### 4.2 `LogicLayout`（D5，新文件 `Layout/LogicLayout.swift`）
总分树，与 `RadialLayout` 同构：
- 根在最左：`center.x = rootPadX + 宽/2`，`isRoot = true, side = nil`。
- 每层：子节点垂直堆叠（`vGap`）于父右侧，`childX = 父右缘 + hGap + 子宽/2`，子列垂直居中于父 `center.y`。
- **L 形正交边**：`start = (父右缘, 父center.y)` → `(子左缘x, 父center.y)` → `(子左缘x, 子center.y)` → `end = (子左缘, 子center.y)`；`side = .right`。
- `NodeFrame.side` 统一 `.right`；**模型层 `Node.side` 不动**（切回辐射左右分组完整）。
- toggle 统一右侧（有子节点即生成，含根）；折叠行为与辐射一致（后代不占空间）。
- 根折叠退化：仅根 frame + 无子边 + 单右 toggle。
- 图片节点照常 `collectImagePayloads`；长文本宽度随 `TextMeasure` 自适应。

---

## 5. Codec v5（FR-L1）

- `MindMapDocument` 增 `var layout: LayoutKind = .radial`；`LayoutKind: String, Codable, Sendable, Equatable, Hashable { case radial, logic }`（同文件）。
- `currentVersion` **4 → 5**。
- **自定义 `init(from:)`**：`layout = try c.decodeIfPresent(LayoutKind.self, forKey: .layout) ?? .radial`（非可选字段必须容错，否则 v4 老文件 decode 抛错）；`encode(to:)` 由编译器合成。自定义 init 带 `layout` 默认参，现有 `MindMapDocument(version:root:)` 调用点不破。
- `LinvaCodec.decode` 末尾追加 `if doc.version == 4 { doc.version = 5 }`（不重写既有 v1–v4 链）。
- **`sanitize` 保留 layout**：重建文档必须 `MindMapDocument(version:root:layout: document.layout)`，否则逻辑图文档消毒后被重置为辐射。
- `sanitize` 的 side 消毒规则**不变**（布局切换不清 side）。

---

## 6. setLayout 命令与会话（FR-L3 / L4）

- **`MindMapCommand`** 增 `case setLayout(kind: LayoutKind)`。
- **`MindMapModel.setLayout(_:) -> LayoutKind?`**：`guard document.layout != kind else { return nil }`（no-op 不入栈）；改 `document.layout` 返回旧值。
- **`CommandBus.applyForward`**：
  ```swift
  case let .setLayout(kind):
      guard let old = model.setLayout(kind) else { return nil }
      return Entry(undo: { _ = self.model.setLayout(old) },
                   redo: { _ = self.model.setLayout(kind) })
  ```
  不改选中态（仿 `setFill`）。
- **`DocumentSession`**：
  - `var layout: LayoutKind { model.document.layout }`（读源单点）。
  - `func setLayout(_ kind:)`：`commitEditingIfNeeded()` → `commandBus.execute(.setLayout(kind:))`（自动 fit 由 `markDirtyAndRelayout` 统一触发，见 §3）。
  - `var canSetSide`：加 `model.document.layout != .logic &&` 前缀（FR-L4）；命令层 `setSide` **不加约束**（保 Undo 历史回放）。

### DropIntent 侧向禁用（FR-L4）
- `resolveDropIntent` 根命中分支：`if .logic` → 跳过左右侧带、直接成子（合法时）。
- `resolveEmptySideIntent`：开头 `guard .logic else { return nil }`。
- 拖拽搬移父子、插入线、插入兄弟不受布局影响。

---

## 7. UI（FR-L3 / L4）

- **工具栏**：`MainToolbar` 增 `let layout: LayoutKind` + `let setLayout: (LayoutKind) -> Void`；automatic 组 `FillSwatchesView` 后加 `Picker("布局", selection: ...).pickerStyle(.menu)`（辐射/逻辑图，D2）。`ContentView` 传 `layout: session.layout, setLayout: { session.setLayout($0) }`。
- **菜单栏 ⌥L**：`DocumentCommands` `after: .undoRedo` 组末尾加切换按钮（当前==辐射 ? 「切换到逻辑图布局」 : 「切换到辐射布局」），`keyboardShortcut("l", modifiers: .option)`。
- **side 置灰**：由 `canSetSide` 一处管三处（工具栏左右按钮 / 菜单栏「移到左/右侧」/ 侧向拖放）。

---

## 8. 导出（FR-L5）

- **PNG**：`PNGExporter.data` 在 `fullyExpanded` 后按 `expanded.layout` switch 到 Radial/LogicLayout 产快照；离屏渲染只消费快照，零改动（Render 层直接 switch，Layout 类型同模块可用，边界脚本只查 `import`）。
- **Markdown**：既有 FR-E2 遍历树结构，不读 layout，**零改动**。
- **`.linva`**：FR-L1 持久化。

---

## 9. 测试

- **CodecTests**：既有 8 处 `version == 4` 断言升 5；新增 `layoutRoundTrip_preservesLogicAndRadial`、`v4FileWithoutLayout_decodesAsRadial`（字面 v4 JSON 无 layout 键 → 零拒绝、version 5、`.radial`）。
- **LogicLayoutTests（新）**：根左缘贴 rootPadX、子节点右侧、兄弟垂直堆叠、L 形边端点、深层右移、折叠隐藏后代 + toggle 右侧、根折叠退化、图片 collectPayloads、长文本宽度自适应不重叠。
- **LayoutPipelineTests**：删 `FakeLayoutEngine` → 分派用例（radial→Radial / logic→Logic 帧一致）。
- **CommandBusTests**：`setLayout` undo/redo 往返；同 kind no-op 不入栈。
- **DocumentSessionTests**：`setLayout` 切快照 + `layout` 属性 + `canSetSide` logic 下 false / 切回辐射 true + undo 往返。
- **DropIntentTests**：logic 下根左右侧带→child；空白过中线侧意图→nil。
- **PNGExporterTests**：logic 文档导出非空 + PNG 魔数（真 Metal 环境跳过）。

---

## 10. 验证与验收

- `scripts/check-boundaries.sh` 绿（新文件仅 import Foundation/CoreGraphics，白名单已覆盖）。
- `xcodebuild test` 全绿。
- 冒烟手动过 PRD §6 验收表 1–9：切换、⌘Z 往返、总分树形态、折叠、side 置灰、保存重开保持、拖拽/插入线、PNG 导出、图片节点。

---

## 修订记录

| 日期 | 说明 |
|------|------|
| 2026-10-02 | 四节设计评审通过，落盘本 spec（决策 D1–D5）。 |
