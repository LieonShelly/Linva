# YMind — Component Spec: Node（节点卡）

> 画布核心元素。Render 层（Metal）绘制；本规格给状态表与精确行为。
> 引用语义 token：`--s-node-*`、`--s-root-*`、`--s-selection-ring`、`--s-fill-*`（见 design-tokens.md）。

---

## 1. 结构

节点卡 = 圆角矩形卡片，内含内容块栈（文本块 / 图片块）。根节点为深底 SF 加粗标题卡。

| 尺寸参数 | 值 | 映射 |
|---|---|---|
| 普通节点圆角 | `--p-radius-m` (8) | `MetalRenderer` |
| 根节点圆角 | `--p-radius-l` (10) | `MetalRenderer` |
| 普通节点 padding | x=16, y=12 | `LayoutConstants.nodePadX/Y` |
| 根节点 padding | x=20, y=16 | `LayoutConstants.rootPadX/Y` |
| 普通节点正文 | 13pt SF Pro | 文字纹理 |
| 根节点正文 | 15–17pt SF Pro 加粗 | 文字纹理 |

---

## 2. 状态表

| 状态 | 底 | 描边 | 阴影/泛光 | 文字 | 动效 |
|---|---|---|---|---|---|
| **默认** | `--s-node-bg` | `--s-node-border` 1.5px | `--p-shadow-2` | `--s-canvas-ink` | — |
| **Hover** | `--s-node-bg` | `--p-accent` 45% 混合 | `--p-shadow-2` | 同上 | `--m-fast` |
| **选中** | `--s-node-bg` | `--p-accent` | `--s-selection-ring`（3px 泛光） | 同上 | `--m-base` |
| **选中+Hover** | `--s-node-bg` | `--p-accent` | 泛光加深 | 同上 | — |
| **锚点（多选起选）** | `--s-node-bg` | 虚线 accent 55% | — | 同上 | `--m-fast` |
| **剪切源（cut）** | `--s-node-bg` | `--s-node-border` 虚线 | `opacity 0.42` | 同上 | `--m-fast` |
| **放置目标（child）** | accent-soft 55% 混底 | `--p-accent` | 泛光 | 同上 | `--m-fast` |
| **编辑中** | `--s-node-bg` | accent 泛光 3px | caret accent | 同上 | `--m-spring-gentle` |

**根节点专属**：

| 状态 | 底 | 文字 | 泛光 |
|---|---|---|---|
| 默认 | `--s-root-bg` | `--s-root-text` | — |
| 选中 | `--s-root-bg` | 白 | accent 泛光 45% |
| 放置（side 左/右） | accent 28% 混底 | 白 | 内侧 6px accent 竖条 |

**填色节点**（覆盖默认底/描边）：

| 状态 | 底 | 描边 |
|---|---|---|
| 普通 + 填色 | `--s-fill-bg` | `--s-fill-border` |
| 根 + 填色 | `--s-fill-root`（深底） | 同底，白字 |

> 选中/搜索命中泛光叠于填色**之上**（现状已如此，保持）。

---

## 3. 行为细则

1. **命中区** = 节点 rect（含 padding）。点空白才取消选中（`hitTestCanvas` 命中顺序：分叉控件→节点→空白）。
2. **双击** 命中图片块 → 进入 `selectedImageBlock` 编辑（⌫ 删块）；双击文本区 → 进入文字编辑。
3. **拖拽**：位移超过 4pt 阈值进入搬枝（`hasExceededDragThreshold`），拖起节点 `opacity 0.55` 置顶。
4. **键盘**：选中后可 Tab 加子 / Return 加同级 / Delete 删除 / ⌫ 删图片块 / Esc 退编辑。
5. **右键** → 节点 context menu（见 `context-menu.md`，**现状缺失，需新增**）。
6. **多行文本**：`pre-wrap`，宽度上限普通 188pt / 根 220pt（`LayoutConstants.nodeMaxTextWidth/rootMaxTextWidth`）。

---

## 4. 无障碍

- 每个节点可被 VoiceOver 聚焦，读出文字 + 选中/折叠状态。
- 折叠状态用「数字徽标」+ 形状双重表达（不只颜色）。
- 选中状态提供非颜色提示（描边 + 泛光环），不单靠颜色。
