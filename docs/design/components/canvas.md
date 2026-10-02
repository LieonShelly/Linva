# YMind 组件规格 — 画布（Canvas）

> 层级：**Metal 层**。画布是 YMind 的核心交互面：纸感底 + 中心辐射树 + 拖放/框选/折叠。只消费 `LayoutSnapshot` + `Camera`，不懂树（`ymind-layout-snapshot` 硬约束）。所有色值引用 `design-tokens.md`，动效引用 `motion-tokens.md`。

---

## 1. 画布表面

| 属性 | 值（引用 token） |
|------|-----------------|
| 底色 | `sem.color.canvas.bg`（纸感底） |
| 中央提亮 | `sem.color.canvas.glow` 径向渐晕（椭圆，聚焦中心主题） |
| 极淡点阵 | `sem.color.canvas.grid`（可选氛围，纸感底弱化，暗色下近乎不可见） |
| clearColor | `sem.color.canvas.bg`（`MetalRenderer` 现从 `windowBackgroundColor` 取 → 改为语义 token） |
| 动效 | `motion.duration.slow` 首屏纸面淡入 |

**布局**：中心主题居中，一级子节点按 `side` 左/右分列；`hGap` 56pt / `vGap` 16pt 枝距（`LayoutConstants`）。

---

## 2. 树连线（Edge）

| 状态 | 属性 | 值 |
|------|------|-----|
| 默认 | 描边 | `sem.color.edge`，`prim.stroke.edge` (1.75pt)，`linecap: round`，opacity 0.75 |
| 过渡 | 控制点插值 | `motion.duration.medium` + `motion.easing.inOut`（搬枝/折叠时平滑） |

**几何**：`EdgeGeometry.points`（父边起点 → 水平中点 ×2 → 子边终点），Render 逐点插值。不与节点矩形重叠。

---

## 3. 分叉折叠钮（BranchToggle）

> **仅在「已折叠」时显示**（2026-10-02 交互修订）：折叠钮是**展开入口**，不是常驻控件。节点展开时无折叠钮，点击**节点本体**即可折叠；折叠后显示 `+N` 钮（N=隐藏数）用于展开。现状 `branchToggleVisualRadius` 11 / `hitRadius` 14；**gap 改 0（贴边）**——折叠钮贴在节点左/右边缘上，不再远离节点。命中区 = 视觉外扩（`branchToggleHitContains`）。

| 状态 | 显示 | 背景 | 边框 | 文字 | 阴影 | 动效 |
|------|------|------|------|------|------|------|
| 节点展开 | **无折叠钮** | — | — | — | — | 点击节点本体 → 折叠 |
| 节点折叠 | `+N` 钮 | `sem.color.accent` | `sem.color.accent` | `sem.color.text.onAccent`（+N） | `prim.shadow.toggle` 加深 | 出现 `motion.duration.fast`；点击 → 展开 |
| 按下 | — | — | — | — | — | `scale 0.96` 按压反馈 |

- 胶囊外框随「+N」位数增宽，封顶 `branchToggleGap`（`branchToggleWorldRect`）。
- **贴边布局**：折叠钮中心落在节点边缘线（`frame.center.x + dir * frame.size.width / 2`，`dir=±1`），视觉半嵌入节点边界，随节点一起走（2026-10-02 修订）。
- **折叠交互**（2026-10-02 修订）：展开节点点击本体即折叠（子树聚合）；折叠节点点击本体或 `+N` 钮即展开（子树散开）。折叠钮仅折叠态出现，作明确的展开入口。

---

## 4. 选中反馈（光环）

| 状态 | 值 |
|------|-----|
| 单选 | `sem.color.accent` 边框 + `sem.color.accent.soft` 3pt 光环（`prim.stroke.ring`） |
| 中心主题选中 | 深底上光环用 `sem.color.text.onRoot` 淡色（原型 `rgba(159,212,192,0.45)`） |
| 多选 | 每个命中节点同款光环，锚点节点加虚线框（`is-anchor`） |
| 动效 | `motion.duration.base` + `motion.easing.inOut` |

---

## 5. 拖放反馈（搬枝 / 插入 / 改侧）

| 意图 | 表现 | 值 |
|------|------|-----|
| 成子 | 目标节点光环 + 淡底 | `sem.color.accent` 光环 + `accent.soft 55%` 底 |
| 插前/插后 | 节点本体弱高亮 + 插入线 | 插入线 = `sem.color.accent` 3pt 圆角线 + 2pt 淡环 |
| 改侧（中心左右 1/3） | 侧引导带 | 垂直引导线 `sem.color.accent` opacity 0.55，中心主题左右镶边 |
| 剪切源 | 弱化 | opacity 0.42 + 虚线边框 |

- 反馈**即时**切换（`DropIntent` 状态机），不拖尾；高亮叠在选中之上。
- 命中优先序：分叉钮 → 节点 → 空白（`CanvasHitTesting`）。

---

## 6. 框选矩形（Marquee）

| 属性 | 值 |
|------|-----|
| 描边 | `sem.color.accent` 1.5pt + 外圈淡环 |
| 底色 | `sem.color.accent.soft` |
| 圆角 | 4pt |
| 动效 | 无（实时跟指针） |
| 触发 | 空白左拖 ≥4pt；⇧ 加选 |

---

## 7. 画布光标状态

| 状态 | 光标 |
|------|------|
| 默认 | 箭头 |
| 空格临时平移 | grab → grabbing |
| 手型工具 | hand.draw → grabbing |
| 框选工具 | crosshair |
| 节点拖拽 | grabbing |

---

## 8. 无障碍 / 合规

- 画布内容（节点/边/折叠钮）均需可键盘触达：Tab 遍历节点、方向键导航、Return 编辑、Delete 删除、空格折叠（菜单栏 + 快捷键兜底）。
- 折叠钮非纯图标：带「−N」数字标签可读；hover/help 提示。

---

## 变更记录
| 日期 | 说明 |
|------|------|
| 2026-10-02 | 修订：折叠钮**仅折叠态显示**（展开入口 `+N`）；展开节点点击本体折叠（产品反馈）。gap 18→0（贴边），中心落节点边缘线 |
| 2026-10-02 | 首版：纸感底 + 连线 + 折叠钮 + 选中/拖放/框选状态表，锚定 `LayoutConstants` / `CanvasHitTesting` |
