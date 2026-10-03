# YMind 组件规格 — 节点（Node）

> 层级：**Metal 层**（画布上绘制；文字编辑浮层归 SwiftUI，见 `node-editor-overlay.md`）。节点是树的视觉单元，分「普通节点」与「中心主题」两种形态。色值引用 `design-tokens.md`，动效引用 `motion-tokens.md`。

---

## 1. 形态

| 形态 | 卡面 | 边框 | 圆角 | 文字 |
|------|------|------|------|------|
| **普通节点** | `sem.color.surface.node` | `prim.color.node.border` 1.5pt | `prim.radius.node` (4pt) | `sem.font.node`（SF Pro 13pt） |
| **中心主题** | `prim.color.root.fill`（深底） | 同卡面（无外框） | `prim.radius.root` (4pt) | `sem.font.root`（SF Pro 17pt semibold），字色 `sem.color.text.onRoot` |
| 阴影 | `prim.shadow.node` | — | — | — |

- 内边距：普通 `nodePadX/Y`（16/10pt），中心 `rootPadX/Y`（22/16pt）。
- 最大宽：普通 188pt / 中心 220pt，多行文本 `lineHeight 20/24pt` 堆叠。

---

## 2. 状态表

| 状态 | 卡面 | 边框 | 光环 | 文字 | 动效 |
|------|------|------|------|------|------|
| **默认** | `sem.color.surface.node` | `node.border` | 无 | `text.primary` | — |
| **hover** | 同上 | `accent 45% + node.border` | 无 | 同 | `motion.duration.fast` |
| **选中** | 同上 | `sem.color.accent` | `accent.soft` 3pt | 同 | `motion.duration.base` |
| **选中+多选锚点** | 同上 | `accent` | 光环 + 虚线框 `accent 55%` | 同 | `base` |
| **剪切源** | 同 | 虚线 `node.border` | 无 | opacity 0.42 | `fast` |
| **drop-target（成子）** | `accent.soft 55% + node` | `accent` | 3pt 光环 | 同 | `fast`（即时） |
| **编辑中** | 同 | `accent` | `accent.soft` 3pt | caret `accent` | —（浮层接管） |

**中心主题差异**：
| 状态 | 卡面 | 光环 |
|------|------|------|
| 选中 | `root.fill` | `text.onRoot` 淡色 3pt（原型 `rgba(159,212,192,0.45)`） |
| 搜索命中 | `root.fill` | `prim.color.search` 3pt（暗色变体加深） |
| 改侧镶边 | `root.fill` | 左/右 `inset 6pt accent` 镶边 |

---

## 3. 填色（NodeFill）

> 现有 `NodeFillStyle` 算法即规格，**不改**。5 token：`sage/sky/sand/rose/lilac` + 默认（无填色）。

| 组合 | 卡面 | 边框 |
|------|------|------|
| 普通节点 + fill | token 浅底 `(s .14, b .94)` light | token 边框 `(s .20, b .58)` |
| 中心主题 + fill | token 深变体 `(s .42, b .30)` light（白字可读） | 同卡面 |

- 填色叠于**选中光环之下**（光环在上，填色在下）；搜索命中描边叠于最上。
- 复制粘贴/搬枝保留 `fill`（剪贴板快照含）。

**折叠交互**（2026-10-02 修订）：有子节点的节点，**点击本体切换折叠**——展开节点点击即折叠（子树聚合），折叠节点点击即展开。折叠态在边缘显示 `+N` 展开钮（见 `canvas.md`）。

---

## 4. 内容块（blocks，图文流 v4）

| 块 | 布局 | 渲染 |
|----|------|------|
| 文本块 | 水平撑满节点宽，块内 vPad 内缩 | `TextAtlas` 按块 id 缓存栅格 |
| 图片块 | 水平居中，等比缩至 `imageMaxDisplayWidth` (300pt)，贴顶 | `ImageTextureCache` + 降采样 |
| 块间距 | `imageTextGap` 6pt（末块后无 gap） | — |
| 图片选中 | 块级光环 + ⌫ 删块 / Esc 先退 | `selectedImageBlock` 会话态 |

---

## 5. 无障碍 / 合规

- 节点文字对比度 ≥ 4.5:1（`sem.color.text.primary` vs `surface.node` 达标）。
- 中心主题字色 `onRoot` 在深底上 ≥ 4.5:1。
- 节点可键盘导航（Tab 遍历、方向键、Return 编辑、Delete 删、空格折叠）。

---

## 变更记录
| 日期 | 说明 |
|------|------|
| 2026-10-02 | 修订：有子节点节点**点击本体切换折叠**（折叠钮仅折叠态显示，产品反馈） |
| 2026-10-02 | 修订：节点圆角 14/18pt → **4pt**（近方角，产品反馈） |
| 2026-10-02 | 首版：普通/中心双形态 + 状态表 + 填色 + 内容块，锚定 `NodeFillStyle` / `LayoutConstants` / 块级渲染 |
