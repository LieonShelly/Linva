---
name: ymind-layout-snapshot
description: YMind 的布局与渲染契约（LayoutSnapshot / NodeFrame / EdgeGeometry / RadialLayout）。当扩展布局算法、修改节点 frame/边几何、或改动 Render 与 Layout 的接缝时使用。
license: proprietary
---

# YMind 布局与 Snapshot 契约

YMind 的核心分层：**CPU 算几何（Layout）→ 产出 `LayoutSnapshot` → Metal 只消费 Snapshot 画像素**。本技能定义这条接缝的不变量。

## 关键文件

- `Layout/LayoutSnapshot.swift` —— `NodeFrame` / `EdgeGeometry` / `BranchToggle` / `LayoutSnapshot`（含 `imagePayloads: [UUID: ImagePayload]`：有图节点的图片载荷，Layout 从 Model 拷出，Render 只消费 Snapshot）
- `Layout/RadialLayout.swift` —— 中心辐射布局算法
- `Layout/TextMeasure.swift`、`Layout/NodeSize.swift`、`Layout/LayoutConstants.swift`
- `Render/CanvasMetalView.swift`、`Render/MetalRenderer.swift` —— 只消费 Snapshot + Camera
- `Session/DocumentSession.swift` —— `relayout()` 触发 `RadialLayout.layout`

## 不变量（违反会破坏分层）

1. **Metal 不理解树**：`MetalRenderer.draw(snapshot:camera:selectedId:)` 只吃 `LayoutSnapshot` + `Camera`，**不允许** Render 访问 `MindMapModel`/`Node`。任何「渲染需要但 Snapshot 没有」的信息，都要先加进 Snapshot，而不是让 Metal 去读模型。
2. **数据流单向**：`Model 变更 → Session.relayout() → RadialLayout.layout() → snapshot → Render.draw()`。Layout 只读 Model，Render 只读 Snapshot。
3. **`LayoutSnapshot` 是稳定接缝**：换布局算法（中心辐射 → 组织图等）或换渲染后端时，只要 Snapshot 契约不变，Render 无需改动。扩展字段时，要**同时**保证 Layout 产出、Render 消费两端一致。
4. **`NodeFrame` 携带渲染所需的一切**：`id / text / center / size / isRoot / side / collapsed / hiddenCount / imageRect`。新增渲染特性（如样式色、图标）应加字段进 `NodeFrame`（以及 Layout 产出它），而不是给 Render 开访问 Model 的口子。
5. **`EdgeGeometry` 是布局专用几何**：含 `fromId / toId / side / points`。若新布局需要不同的边几何，扩 `EdgeGeometry`，而非让 Metal 懂业务。

## RadialLayout 不变量

- **side 只存根下第一层**：根的直接子节点存 `left`/`right`；更深节点继承所在侧（`side` 为 `nil`）。布局时用 `frame.side` 推导。
- **折叠**：折叠子树高度视为 0（只留节点自身），布局自然收缩。`NodeFrame.hiddenCount` 表示折叠隐藏的后代数。
- **BranchToggle 生成规则**（`makeBranchToggles`）：
  - 非根节点：有子节点且 `frame.side` 非空 → 生成一个 toggle；
  - 根节点：分别对左、右两侧，`collapsed || 该侧有子` 才生成对应 toggle（根可左右各一个折叠按钮）。
- 布局输入：`document + TextMeasure`；输出 `LayoutSnapshot`。

## 扩展布局的步骤

1. 若加第二种布局：把 `RadialLayout` 抽成 `protocol LayoutEngine { func layout(document:measure:) -> LayoutSnapshot }`，Session 持有当前 engine（见 `docs/架构现状.md` §7.3）。**当前 `RadialLayout` 是 enum + static，尚未协议化**。
2. 扩 `NodeFrame`/`EdgeGeometry`/`BranchToggle` 字段：先定 Layout 如何产出，再定 Render 如何消费。
3. 保持 `LayoutSnapshot` 的 Equatable 语义（用于 dirty 判断）。

## 验证

- `RadialLayoutTests` 覆盖：树 → frame/边 的正确性、折叠收缩、side 继承、BranchToggle 生成。
- 渲染改动后：跑 App 目测节点位置、连线、折叠按钮与折叠状态一致（Render 层偏手测，见 `docs/架构现状.md` §7.4 的回归手测清单）。
