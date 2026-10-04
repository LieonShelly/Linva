---
name: ymind-layout-snapshot
description: YMind 的布局与渲染契约（LayoutSnapshot / NodeFrame / EdgeGeometry / RadialLayout）。当扩展布局算法、修改节点 frame/边几何、或改动 Render 与 Layout 的接缝时使用。
license: proprietary
---

# YMind 布局与 Snapshot 契约

YMind 的核心分层：**CPU 算几何（Layout）→ 产出 `LayoutSnapshot` → Metal 只消费 Snapshot 画像素**。本技能定义这条接缝的不变量。

## 关键文件

- `Layout/LayoutSnapshot.swift` —— `NodeFrame` / `EdgeGeometry` / `BranchToggle` / `LayoutSnapshot`（含 `imagePayloads: [UUID: ImagePayload]`：有图节点的图片载荷，Layout 从 Model 拷出，Render 只消费 Snapshot）
- `Layout/RadialLayout.swift` —— 中心辐射布局算法（`.radial`）
- `Layout/LogicLayout.swift` —— 逻辑图（总分树）布局算法（`.logic`）：根最左、层级向右、L 形边
- `Layout/LayoutSupport.swift` —— 两引擎共享辅助（测高 / 块居中 / 图片载荷收集 / toggle 生成）
- `Layout/LayoutEngine.swift` —— 布局引擎协议
- `Layout/TextMeasure.swift`、`Layout/NodeSize.swift`、`Layout/LayoutConstants.swift`
- `Render/CanvasMetalView.swift`、`Render/MetalRenderer.swift` —— 只消费 Snapshot + Camera
- `Session/LayoutPipeline.swift` —— 按 `document.layout` 分派引擎
- `Session/DocumentSession.swift` —— `relayout()` 经 `LayoutPipeline` 触发

## 不变量（违反会破坏分层）

1. **Metal 不理解树**：`MetalRenderer.draw(snapshot:camera:selectedId:)` 只吃 `LayoutSnapshot` + `Camera`，**不允许** Render 访问 `MindMapModel`/`Node`。任何「渲染需要但 Snapshot 没有」的信息，都要先加进 Snapshot，而不是让 Metal 去读模型。
2. **数据流单向**：`Model 变更 → Session.relayout() → LayoutPipeline 按 document.layout 分派引擎（RadialLayout / LogicLayout）→ snapshot → Render.draw()`。Layout 只读 Model，Render 只读 Snapshot。
3. **`LayoutSnapshot` 是稳定接缝**：换布局算法（中心辐射 → 组织图等）或换渲染后端时，只要 Snapshot 契约不变，Render 无需改动。扩展字段时，要**同时**保证 Layout 产出、Render 消费两端一致。
4. **`NodeFrame` 携带渲染所需的一切**：`id / text / center / size / isRoot / side / collapsed / hiddenCount / imageRect`。新增渲染特性（如样式色、图标）应加字段进 `NodeFrame`（以及 Layout 产出它），而不是给 Render 开访问 Model 的口子。
5. **`EdgeGeometry` 是布局专用几何**：含 `fromId / toId / side / points`。若新布局需要不同的边几何，扩 `EdgeGeometry`，而非让 Metal 懂业务。

## RadialLayout 不变量

- **side 只存根下第一层**：根的直接子节点存 `left`/`right`；更深节点继承所在侧（`side` 为 `nil`）。布局时用 `frame.side` 推导。
- **折叠**：折叠子树高度视为 0（只留节点自身），布局自然收缩。`NodeFrame.hiddenCount` 表示折叠隐藏的后代数。
- **根左右独立折叠（v6）**：根折叠态由 `collapsedLeft`/`collapsedRight` 独立承载（非根仍用单值 `collapsed`）。布局时折叠侧的子节点不参与测高与排布（`RadialLayout` 过滤 `visibleRootChildren` 并保持 `rootMetadata.children` index 对齐）；全折叠（两侧皆折）早退只画根。toggle 的 `collapsed`/`hiddenCount` 按各自侧独立（`makeToggle` 显式重载 + `countDescendants(node, side:)`）。
- **BranchToggle 生成规则**（`makeBranchToggles`）：
  - 非根节点：有子节点且 `frame.side` 非空 → 生成一个 toggle；
  - 根节点：分别对左、右两侧，`collapsedLeft/collapsedRight || 该侧有子` 才生成对应 toggle（根可左右各一个折叠按钮，各自独立折叠态）。
- 布局输入：`document + TextMeasure`；输出 `LayoutSnapshot`。

## LogicLayout 不变量（逻辑图 / 总分树）

- **根在最左、层级向右层层展开**；所有节点统一 `.right` side（无左右分组语义）。
- **L 形边**：`EdgeGeometry.points` 为「水平出 → 垂直拐 → 水平入」四点折线。
- **BranchToggle 一律在右侧**（`LayoutSupport.makeToggle(..., side: .right)`）；折叠子树高度视为 0、不占空间。
- **根折叠（v6）**：逻辑图无左右侧语义，根折叠 = 左右两侧独立折叠的**聚合态**（`collapsedLeft && collapsedRight` 视为整树折叠，早退只画根；部分折叠时仍显示全部子节点）。根 toggle 的 `collapsed`/`hiddenCount` 按聚合态。
- **side 降级（FR-L4）**：逻辑图下 `DocumentSession.canSetSide == false`（⌘←/⌘→ 置灰、`DropIntent` 侧向放置禁用），切回辐射恢复。

## 扩展布局的步骤

1. **双引擎已落地**：`LayoutEngine` 协议（`static func layout(document:measure:) -> LayoutSnapshot`）+ `LayoutPipeline` 按 `document.layout` 分派（`.radial → RadialLayout`、`.logic → LogicLayout`，见 `docs/架构现状.md` §7.10）。加第三种布局：`LayoutKind` 增 case → 新类型实现 `LayoutEngine`（共享辅助优先复用 `LayoutSupport`）→ `LayoutPipeline` switch 加分派，Session / Render 零改动。
2. 扩 `NodeFrame`/`EdgeGeometry`/`BranchToggle` 字段：先定 Layout 如何产出，再定 Render 如何消费。
3. 保持 `LayoutSnapshot` 的 Equatable 语义（用于 dirty 判断）。

## 验证

- `RadialLayoutTests` / `LogicLayoutTests` 覆盖：树 → frame/边 的正确性、折叠收缩、side 继承、BranchToggle 生成；`LayoutPipelineTests` 覆盖按 `document.layout` 分派。
- 渲染改动后：跑 App 目测节点位置、连线、折叠按钮与折叠状态一致（Render 层偏手测，见 `docs/架构现状.md` §7.4 的回归手测清单）。
