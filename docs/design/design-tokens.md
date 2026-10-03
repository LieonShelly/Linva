# YMind — Design Tokens

> 设计真源（单一事实来源）。三层 token 架构：**primitive → semantic → component**。
> 所有开发者可见的数值一律来自语义 token；不暴露裸 hex / 裸 px。
> 本文件与 `motion-tokens.md`、`components/*.md`、`prototype/design/*.html` 配套。
>
> **品牌基调（2026-10 定案）**：亮色 = 系统原生（System），暗色 = 深色沉浸（Dark Immersive）。
> 全 SF Pro 无衬线；无纸感、无点阵、无自定义标题栏。chrome 用系统材质；画布、节点、
> 连线随外观解析。填色沿用现有 5 色 token（`sage/sky/sand/rose/lilac`）作为分类工具。
> 对比原型见 `prototype/design/schemes.html`（方案 A/D），选型依据见 `docs/design/schemes.md`。
>
> **可落地性红线**：Render 层（Metal）只吃 `LayoutSnapshot + Camera`，颜色经 `NodeFillStyle`
> （`appearanceAware` 动态 `NSColor`）派生；本文所有 color token 标注其映射到哪个现有实现点。

---

## 1. 设计原则

1. **原生外壳，克制色彩**：窗口 chrome 用 macOS 系统材质与语义色；画布亮色取系统
   `windowBackgroundColor`（与 Finder/备忘录同款），暗色取近黑沉浸底；两者都符合 HIG。
2. **单一 accent，随系统**：亮色 accent = 系统蓝 `#0a84ff`（跟随 `controlAccentColor` 语义）；
   节点填色 5 色是「分类工具」而非装饰。
3. **系统字体**：全 SF Pro（`-apple-system` / `.systemFont`）；根节点用 SF Pro 加粗承载
   「标题感」，不引入衬线/第三方字体（New York 方案已废弃）。
4. **亮暗双态自适应**：所有 color token 走动态 `NSColor`（`NodeFillStyle` 模式），随外观
   自动解析，尊重 Increase Contrast / Reduce Transparency。
5. **8pt 网格**：间距、圆角、节点 padding 都落在 4pt/8pt 网格上；圆角取系统控件阶梯。

---

## 2. Primitive Tokens（原始值）

> 仅在此层出现裸值。**语义层、组件层不得再写裸值**，一律 `var(--…)` 引用。

### 2.1 Color — 亮色=系统原生 A（画布/节点/连线）

| Primitive | Light (A) | Dark (D) | 说明 |
|---|---|---|---|
| `--p-canvas` | `#ececec` | `#171719` | 画布底（亮 = 系统 `windowBackgroundColor`；暗 = 沉浸近黑） |
| `--p-node` | `#ffffff` | `#262628` | 节点卡底 |
| `--p-node-border` | `#d1d1d6` | `#3c3c3f` | 节点描边（亮 = 系统 `separatorColor` 系） |
| `--p-root-fill` | `#3a3a3c` | `#0a84ff` | 根节点底（亮 = 深中性；暗 = accent 蓝点亮） |
| `--p-root-text` | `#ffffff` | `#ffffff` | 根节点字 |
| `--p-ink` | `#1d1d1f` | `#f2f2f4` | 主文字（亮/暗 = 系统 labelColor 系） |
| `--p-ink-muted` | `#6e6e73` | `#9a9aa0` | 次级文字 |
| `--p-accent` | `#0a84ff` | `#0a84ff` | accent（亮 = 系统 `controlAccentColor` 蓝；暗同） |
| `--p-accent-soft` | `rgba(10,132,255,.14)` | `rgba(10,132,255,.26)` | accent 泛光 |
| `--p-danger` | `#d70015` | `#ff453a` | 危险操作（系统 red 系） |
| `--p-line` | `#c7c7cc` | `#3a3a3e` | 连线（亮 = 系统 `separatorColor`；暗 = 中灰） |
| `--p-line-hover` | `#0a84ff` | `#64a8ff` | 连线上浮 hover（可选） |
| `--p-search-hit` | `#ff9f0a` | `#ff9f0a` | 搜索命中（系统 orange，与选中区分） |

### 2.2 Color — 节点填色 5 token（亮 / 暗）

> 与 `NodeFillStyle.hue` 一致；`appearanceAware(hue:light:dark:)` 派生。下表为亮暗的 s/b 档位
> （HSB），身份色相固定。亮色档位比旧暖纸方案**更低饱和**（融入系统原生），暗色档位取
> D 方案的深色低饱和卡底。

| Token | Hue | Light (s,b) | Dark (s,b) | 身份 |
|---|---|---|---|---|
| `sage` | 0.34 | (0.14, 0.94) 底 / (0.42,0.30) 根 | (0.24,0.26) 底 / (0.38,0.36) 根 | 绿 |
| `sky` | 0.57 | 蓝 | 蓝 | 蓝 |
| `sand` | 0.10 | 暖金 | 暖金 | 金 |
| `rose` | 0.01 | 粉 | 粉 | 粉 |
| `lilac` | 0.74 | 紫 | 紫 | 紫 |

> 精确 s/b 档位以 `NodeFillStyle` 现行为准；设计侧只承诺「身份色相 + 语义明度」契约，
> 不锁死数值（避免与实现漂移）。亮色若嫌彩，可整体降饱和 10–15% 再定档。

### 2.3 Typography — 系统字体（全 SF Pro）

| Primitive | 值 |
|---|---|
| `--p-font-ui` | SF Pro（`-apple-system` / `.systemFont`） |
| `--p-font-mono` | SF Mono（`.systemFont(design:.monospaced)`）— 缩放计数用 |

> 废弃 `--p-font-display`（New York）——根节点用 SF Pro 加粗（weight .semibold/.bold）。

字号阶梯（pt，macOS 逻辑点）：

| Token | 值 | 用途 |
|---|---|---|
| `--p-fs-11` | 11 | 辅助 / 计数 / 徽标 |
| `--p-fs-12` | 12 | caption |
| `--p-fs-13` | 13 | body / 节点正文 |
| `--p-fs-15` | 15 | 根节点正文（SF 加粗） |
| `--p-fs-17` | 17 | 根节点标题（SF 加粗） |
| `--p-fs-22` | 22 | 浮层大标题 |

### 2.4 Spacing（8pt 网格）

| Token | 值 |
|---|---|
| `--p-space-1` | 4 |
| `--p-space-2` | 8 |
| `--p-space-3` | 12 |
| `--p-space-4` | 16 |
| `--p-space-5` | 20 |
| `--p-space-6` | 24 |
| `--p-space-8` | 32 |

### 2.5 Radius（系统控件阶梯）

| Token | 值 | 说明 |
|---|---|---|
| `--p-radius-s` | 6 | 工具条按钮 hover 底 |
| `--p-radius-m` | 8 | **普通节点圆角**（对齐系统控件） |
| `--p-radius-l` | 10 | **根节点圆角** / 浮层 |
| `--p-radius-xl` | 14 | 大浮层（少用） |
| `--p-radius-pill` | 999 | 分叉控件 / 胶囊 |

> 旧值 14/18（节点/根）过大，已收敛到 8/10（系统原生观感）。

### 2.6 Elevation（阴影 / 描边）

| Token | 值 |
|---|---|
| `--p-shadow-1` | `0 1px 2px rgba(0,0,0,.06), 0 2px 8px rgba(0,0,0,.05)` 轻（节点卡） |
| `--p-shadow-2` | `0 1px 2px rgba(0,0,0,.06), 0 3px 10px rgba(0,0,0,.07)` 浮层 |
| `--p-shadow-dark-1` | `0 1px 2px rgba(0,0,0,.4), 0 2px 8px rgba(0,0,0,.35)` 暗色轻 |
| `--p-shadow-dark-2` | `0 1px 2px rgba(0,0,0,.5), 0 4px 14px rgba(0,0,0,.5)` 暗色浮层 |
| `--p-stroke-1` | 1px 常态描边 |
| `--p-stroke-2` | 1.5px 强调描边 |
| `--p-stroke-3` | 3px 选中/泛光环 |

---

## 3. Semantic Tokens（语义别名）

> 语义层表达「用途」，不表达「值」。组件层引用语义层。

### 3.1 Canvas 画布

| Semantic | 引用 | 说明 / 实现映射 |
|---|---|---|
| `--s-canvas-bg` | `--p-canvas` | 画布底色 → **MetalRenderer 在线 clearColor**，改动态 `NSColor`（亮 `windowBackgroundColor`，暗 `#171719`） |
| `--s-canvas-ink` | `--p-ink` | 画布文字 → 文字纹理主色 |
| `--s-canvas-ink-muted` | `--p-ink-muted` | 次级文字 |
| `--s-edge` | `--p-line` | 连线颜色 → `EdgeGeometry` 渲染色 |
| `--s-edge-hover` | `--p-line-hover` | 连线上浮 hover（可选） |

> 废弃 `--s-canvas-bg-deep`（纸面深度渐变）：无纸感，无渐变底。

### 3.2 Node 节点

| Semantic | 引用 | 实现映射 |
|---|---|---|
| `--s-node-bg` | `--p-node` | 节点卡底 |
| `--s-node-border` | `--p-node-border` | 节点描边 |
| `--s-node-radius` | `--p-radius-m`(8) | 节点圆角 |
| `--s-root-bg` | `--p-root-fill` | 根节点底 |
| `--s-root-text` | `--p-root-text` | 根节点字 |
| `--s-root-radius` | `--p-radius-l`(10) | 根节点圆角 |
| `--s-node-pad-x` | `--p-space-4`(16) | 节点水平 padding → `LayoutConstants.nodePadX` |
| `--s-node-pad-y` | `--p-space-3`(12) | 节点垂直 padding → `LayoutConstants.nodePadY`（现 10，统一到 12） |
| `--s-root-pad-x` | `--p-space-5`(20) | → `LayoutConstants.rootPadX`（现 22） |
| `--s-root-pad-y` | `--p-space-4`(16) | → `LayoutConstants.rootPadY` |
| `--s-selection-ring` | `--p-accent-soft` + `--p-stroke-3` | 选中泛光 |

### 3.3 Fill 填色（语义化 5 色）

| Semantic | 引用 | 用途 |
|---|---|---|
| `--s-fill-bg` | `NodeFillStyle.background(_:)` | 节点填色底 |
| `--s-fill-border` | `NodeFillStyle.border(_:)` | 填色节点边框 |
| `--s-fill-root` | `NodeFillStyle.rootBackground(_:)` | 填色根节点深底 |
| `--s-fill-swatch` | `NodeFillStyle.swatch(_:)` | 工具条色点 |

### 3.4 Chrome 外壳

| Semantic | 引用 | 说明 |
|---|---|---|
| `--s-chrome-bg` | 系统 `windowBackgroundColor` / `.regularMaterial` | 工具条、浮层（**保持系统**） |
| `--s-chrome-sep` | `Color.secondary.opacity(0.15)` | 工具条分组分隔 |
| `--s-tint` | 系统 accent（`controlAccentColor`） | 交互高亮（遵循系统 accent） |

### 3.5 状态

| Semantic | 引用 | 用途 |
|---|---|---|
| `--s-danger` | `--p-danger` | 删除 / 危险 |
| `--s-focus-ring` | `--p-accent-soft` | 焦点环 |
| `--s-disabled-fg` | 系统 `disabledControlTextColor` | 禁用文字 |
| `--s-search-hit` | `--p-search-hit` | 搜索命中高亮（橙，与选中区分） |

---

## 4. Component Tokens（组件层）

> 每个组件一个语义集合，组件规格文档引用这些 token。

### 4.1 Toolbar

| Token | 值 |
|---|---|
| `--c-toolbar-btn-hover-bg` | 系统 hover（黑 6% / 白 9%） |
| `--c-toolbar-btn-radius` | `--p-radius-s`(6) |
| `--c-toolbar-btn-h` | 28pt（macOS 紧凑控件） |
| `--c-toolbar-group-gap` | `--p-space-2` |
| `--c-toolbar-sep` | `--s-chrome-sep` |

### 4.2 SearchBar

| Token | 值 |
|---|---|
| `--c-search-w` | 240pt |
| `--c-search-radius` | `--p-radius-pill` |
| `--c-search-h` | 28pt |
| `--c-search-bg` | 系统 `searchFieldBackgroundColor` |

### 4.3 BranchToggle（分叉控件）

| Token | 值 | 映射 |
|---|---|---|
| `--c-toggle-radius` | `--p-radius-pill` | |
| `--c-toggle-h` | 22pt | → `LayoutConstants.branchToggleVisualRadius*2` |
| `--c-toggle-gap` | 18pt | → `LayoutConstants.branchToggleGap` |
| `--c-toggle-collapsed-bg` | `--p-accent` | 折叠态实心 |
| `--c-toggle-idle-bg` | `--p-node` | 展开态白底 |

### 4.4 NodeEditorOverlay（编辑浮层）

| Token | 值 |
|---|---|
| `--c-edit-bg` | 系统 `.background` |
| `--c-edit-ring` | 系统 `.tint` 2px |
| `--c-edit-radius` | `--p-radius-m` |
| `--c-edit-inset` | `NSSize(8,7)`（维持现状） |

### 4.5 ImportPreview / RecoveryBanner

| Token | 值 |
|---|---|
| `--c-popover-bg` | `.regularMaterial` |
| `--c-popover-radius` | `--p-radius-l`(10) |
| `--c-popover-shadow` | `--p-shadow-2` |

---

## 5. 亮暗对照速查

| 元素 | Light (A 系统原生) | Dark (D 深色沉浸) |
|---|---|---|
| 画布底 | `#ececec` 系统灰 | `#171719` 近黑 |
| 节点卡 | `#ffffff` | `#262628` |
| 节点描边 | `#d1d1d6` | `#3c3c3f` |
| 根节点底 | `#3a3a3c` 深中性 | `#0a84ff` accent 蓝 |
| 根节点字 | `#ffffff` | `#ffffff` |
| 主文字 | `#1d1d1f` | `#f2f2f4` |
| 连线 | `#c7c7cc` | `#3a3a3e` |
| accent | `#0a84ff` | `#0a84ff` |
| 搜索命中 | `#ff9f0a` | `#ff9f0a` |

---

## 6. 与现有实现的映射清单（落地时对照）

| Token | 现有实现点 | 需改动 |
|---|---|---|
| `--s-canvas-bg` | `MetalRenderer` 在线 `clearColor` = `NSColor.windowBackgroundColor` | ✅ 亮色已是系统灰（保持）；补暗色动态色 `#171719`（改动态 `NSColor`） |
| `--s-edge` | `EdgeGeometry` → `MetalRenderer` 画线 | 亮 `#6d7568`→`#c7c7cc`；暗 `#7d8375`→`#3a3a3e` |
| `--s-node-*` | `MetalRenderer` 节点绘制 + `LayoutConstants` | 圆角 14→8、根 18→10；`nodePadY` 10→12、`rootPadX` 22→20；根节点底改 `#3a3a3c`(亮)/`#0a84ff`(暗) |
| `--s-root-*` | `MetalRenderer` 根节点绘制 + 文字纹理 | 字体 New York→SF Pro 加粗（**根节点衬线方案废弃**） |
| `--s-fill-*` | `NodeFillStyle` | 已符合，契约对齐即可（亮色可整体降饱和 10–15%） |
| `--s-chrome-bg` | `MainToolbar` / 浮层 `.regularMaterial` | 保持 |
| `--c-toggle-*` | `LayoutConstants.branchToggle*` + `BranchToggleAtlas` | 视觉微调对齐 token（展开态白底、折叠态 accent 实心，现状已符合） |
| 字体 | `NodeEditorOverlay`（SF）、节点纹理栅格化 | 根节点改 SF Pro 加粗 |
| 根节点文字色 | `drawText` 中 `frame.isRoot ? .white : .labelColor` | 保持（根底亮暗均深/彩，白字可读） |

> **重要**：PNG 导出底色现为固定 `#ececec`（亮，系统灰）——与新的亮色画布一致，**不改**；
> 暗色导出待定（可固定亮底保证品牌一致，或按当前外观导出）。

---

## 7. 验收要点

- [ ] 画布在线底：亮 = 系统灰 `windowBackgroundColor`，暗 = `#171719`（动态 `NSColor`）
- [ ] 根节点字体 = SF Pro 加粗（无衬线）；UI chrome = SF Pro
- [ ] 节点圆角 8 / 根节点 10（系统阶梯），所有间距落 4pt/8pt 网格
- [ ] 根节点底：亮 `#3a3a3c` / 暗 `#0a84ff`，白字
- [ ] 连线：亮 `#c7c7cc` / 暗 `#3a3a3e`，1.75pt
- [ ] 无纸感背景、无点阵、无自定义标题栏（原型 `index.html` 仅作参考，`schemes.html` 为准）
- [ ] 无任何裸 hex 泄漏到 Swift 视图层（只在 primitive / `NodeFillStyle`）
