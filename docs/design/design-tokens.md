# Linva Design Tokens

> 状态：正式 UI/UX 设计基线（2026-10-02）。本文件为**唯一真源**：开发者只消费语义/组件 token，绝不直接写裸 hex/px。亮色 + 暗色双外观。
>
> 设计基调（已拍板）：**温和暖纸品牌 · 单画布专注 · 纸感底 · 收敛工具条**。
> 现有实现锚点：`prototype/styles.css :root` 的暖纸体系、`Render/NodeFillStyle.swift`（5 色系统语义派生）、`Layout/LayoutConstants.swift`、PNG 导出纸面底色 `#e7e4dc`。

---

## 0. Token 架构（三层）

```
Primitive（裸值）── 颜色/字体/尺寸/圆角/阴影/描边的原始定义
      ↓ 语义别名
Semantic（用途别名）── 按「画布 / 表面 / 文字 / 强调 / 反馈」表达用途
      ↓ 组件绑定
Component（组件专用）── 具体到某组件某状态的最终取值
```

- **命名**：`prim.` / `sem.` / `cmp.` 前缀。
- **双外观**：每个颜色 token 给出 `light` 与 `dark` 两值；实现层用 `NSColor(name:resolutionHandler:)`（现状 `NodeFillStyle.appearanceAware` 同款）随系统外观解析。
- **本仓库映射**：SwiftUI 壳用 `Color(nsColor:)`；Metal 画布用 `rgba(NSColor…)`（`MetalRenderer` 已按此模式从 `windowBackgroundColor` 取 clearColor）。

---

## 1. Primitive tokens（裸值）

### 1.1 颜色 primitives

**暖纸中性轴**（纸感品牌核心）：

| token | light | dark | 来源 / 用途 |
|------|-------|------|-----------|
| `prim.color.paper.0` | `#F6F4EE` | `#17181A` | 画布最亮提亮带（径向光） |
| `prim.color.paper.1` | `#E7E4DC` | `#202124` | **纸面底色** = PNG 导出底 `#e7e4dc` |
| `prim.color.paper.2` | `#D8D3C8` | `#2A2B2F` | 纸面渐沉底 |
| `prim.color.panel` | `#F4F1EA` | `#26272B` | 工具条/浮层表面（原 `--panel`） |
| `prim.color.node` | `#FBFAF6` | `#333438` | 节点卡面（原 `--node`） |
| `prim.color.node.border` | `#C8C2B4` | `#4A4B50` | 节点默认边框（原 `--node-border`） |
| `prim.color.ink` | `#1A1C19` | `#ECE9E2` | 主文字（原 `--ink`） |
| `prim.color.ink.muted` | `#5C6358` | `#A9ACA4` | 次要文字（原 `--ink-muted`） |
| `prim.color.root.fill` | `#1F2A24` | `#0F1712` | 中心主题深底（原 `--root-fill`） |
| `prim.color.root.text` | `#F4F1EA` | `#E7E4DC` | 中心主题字（原 `--root-text`） |
| `prim.color.line` | `#6D7568` | `#8A8E86` | 边线/连线（原 `--line`） |

**强调轴**（Linva 品牌绿）：

| token | light | dark | 用途 |
|------|-------|------|------|
| `prim.color.accent` | `#2F6F5E` | `#6BBFA8` | 主强调（选中/焦点/主操作） |
| `prim.color.accent.soft` | `rgba(47,111,94,0.16)` | `rgba(107,191,168,0.22)` | 强调淡底/选中光环 |
| `prim.color.danger` | `#9B3D2E` | `#E28A78` | 删除/危险（原 `--danger`） |
| `prim.color.search` | `#C4782A` | `#E0A054` | 搜索命中描边（现状已用 `#c4782a`） |

**5 色填色 token（品牌识别色）**——保留身份色相，明度随外观解析（现状 `NodeFillStyle` 已实现，直接沿用）：

| token | hue (HSB) | light `(s,b)` | dark `(s,b)` | 用途 |
|------|-----------|--------------|--------------|------|
| `prim.color.fill.sage` | 0.34 | (0.14, 0.94) | (0.24, 0.26) | 鼠尾草绿 |
| `prim.color.fill.sky` | 0.57 | (0.14, 0.94) | (0.24, 0.26) | 天蓝 |
| `prim.color.fill.sand` | 0.10 | (0.14, 0.94) | (0.24, 0.26) | 暖金 |
| `prim.color.fill.rose` | 0.01 | (0.14, 0.94) | (0.24, 0.26) | 粉红 |
| `prim.color.fill.lilac` | 0.74 | (0.14, 0.94) | (0.24, 0.26) | 紫 |

> 填色派生规则（`NodeFillStyle` 现有实现，勿改动算法，仅确认对齐）：
> - 普通节点浅底：`appearanceAware(hue, light:(0.14,0.94), dark:(0.24,0.26))`
> - 普通节点边框：`light:(0.20,0.58), dark:(0.30,0.52)`
> - 中心主题深变体：`light:(0.42,0.30), dark:(0.38,0.36)`（白字可读）
> - 色点（swatch）：`light:(0.30,0.82), dark:(0.40,0.62)`

### 1.2 排版 primitives

> **平台硬约束**：macOS 主 UI 用 **SF Pro（系统字体）**，代码用 SF Mono。`prim.color` 暖纸品牌气质靠**纸面色 + 圆角 + 阴影 + 字重**承载，**不引入 Fraunces/Outfit 等自定义字体**（与系统观感冲突，且 HIG 9.1 要求系统字体）。原型里的 `Fraunces/Outfit` 仅作 HTML 演示近似，不是原生规格。

| token | 值 | 说明 |
|------|-----|------|
| `prim.font.family.ui` | SF Pro（`.system`） | 全部 UI 与节点正文 |
| `prim.font.family.display` | SF Pro 加重（`Weight.semibold`~`bold`） | 中心主题/标题，用字重而非字体切换 |
| `prim.font.size.node` | 13pt | 节点正文（现状 `NSFont.systemFontSize` 对齐） |
| `prim.font.size.root` | 17pt | 中心主题 |
| `prim.font.size.caption` | 11pt | 辅助/计数 |
| `prim.font.size.toolbar` | 13pt | 工具条 |
| `prim.font.line.node` | 1.35 | 节点行高 |
| `prim.font.weight.root` | semibold | 中心主题字重 |

### 1.3 尺寸 / 间距 primitives

> 直接锚定 `Layout/LayoutConstants.swift`（改布局常量走 `linva-layout-snapshot`）。

| token | 值 | 映射 |
|------|-----|------|
| `prim.space.4` | 4pt | |
| `prim.space.6` | 6pt | `imageTextGap` |
| `prim.space.8` | 8pt | |
| `prim.space.12` | 12pt | |
| `prim.space.16` | 16pt | `nodePadX` / `vGap` |
| `prim.space.20` | 20pt | |
| `prim.space.22` | 22pt | `rootPadX` |
| `prim.space.56` | 56pt | `hGap` 水平枝距 |
| `prim.layout.node.padX` | 16pt | `nodePadX` |
| `prim.layout.node.padY` | 10pt | `nodePadY` |
| `prim.layout.root.padX` | 22pt | `rootPadX` |
| `prim.layout.root.padY` | 16pt | `rootPadY` |
| `prim.layout.maxW.node` | 188pt | `nodeMaxTextWidth` |
| `prim.layout.maxW.root` | 220pt | `rootMaxTextWidth` |
| `prim.layout.line.node` | 20pt | `nodeLineHeight` |
| `prim.layout.line.root` | 24pt | `rootLineHeight` |
| `prim.layout.image.maxW` | 300pt | `imageMaxDisplayWidth` |
| `prim.layout.toggle.gap` | 0pt（贴边） | `branchToggleGap` 改 0：折叠钮贴节点边缘，不再远离 |
| `prim.layout.toggle.visualR` | 11pt | `branchToggleVisualRadius` |
| `prim.layout.toggle.hitR` | 14pt | `branchToggleHitRadius` |

### 1.4 圆角 / 阴影 / 描边 primitives

| token | light | dark |
|------|-------|------|
| `prim.radius.node` | 4pt | 4pt |
| `prim.radius.root` | 4pt | 4pt |
| `prim.radius.card` | 10pt | 10pt（浮层/横幅） |
| `prim.radius.pill` | 999pt | 999pt（胶囊/色点） |
| `prim.radius.input` | 8pt | 8pt |
| `prim.shadow.node` | `0 10px 28px rgba(26,28,25,0.10)` | `0 10px 28px rgba(0,0,0,0.45)` |
| `prim.shadow.toggle` | `0 2px 8px rgba(26,28,25,0.12)` | `0 2px 8px rgba(0,0,0,0.5)` |
| `prim.stroke.node` | 1.5pt | 1.5pt |
| `prim.stroke.edge` | 1.75pt | 1.75pt |
| `prim.stroke.ring` | 3pt | 3pt（选中光环） |
| `prim.stroke.marquee` | 1.5pt | 1.5pt |

---

## 2. Semantic tokens（用途别名）

### 2.1 画布 / 表面

| token | 值（light） | 值（dark） | 用途 |
|-------|-----------|-----------|------|
| `sem.color.canvas.bg` | `prim.color.paper.1` | `prim.color.paper.1.dark` | Metal clearColor + 纸感底 |
| `sem.color.canvas.glow` | `prim.color.paper.0` | `prim.color.paper.0.dark` | 画布中央径向提亮 |
| `sem.color.canvas.grid` | `prim.color.ink @ 10%` | `prim.color.ink.dark @ 10%` | 极淡点阵（可选，纸感底弱化） |
| `sem.color.surface.toolbar` | `prim.color.panel` | `prim.color.panel.dark` | 工具条/搜索条表面 |
| `sem.color.surface.overlay` | `prim.color.panel` | `prim.color.panel.dark` | 浮层/横幅/导入预览 |
| `sem.color.surface.node` | `prim.color.node` | `prim.color.node.dark` | 节点卡面 |

### 2.2 文字

| token | light | dark | 用途 |
|-------|-------|------|------|
| `sem.color.text.primary` | `prim.color.ink` | `prim.color.ink.dark` | 正文 |
| `sem.color.text.secondary` | `prim.color.ink.muted` | `prim.color.ink.muted.dark` | 次要/计数/提示 |
| `sem.color.text.onRoot` | `prim.color.root.text` | `prim.color.root.text.dark` | 中心主题上字 |
| `sem.color.text.onAccent` | `#FFFFFF` | `#0F1712` | 强调底上字（折叠钮等） |

### 2.3 强调 / 反馈

| token | light | dark | 用途 |
|-------|-------|------|------|
| `sem.color.accent` | `prim.color.accent` | `prim.color.accent.dark` | 选中/焦点/主操作/插入线/拖放 |
| `sem.color.accent.soft` | `prim.color.accent.soft` | `prim.color.accent.soft.dark` | 选中光环/淡底 |
| `sem.color.danger` | `prim.color.danger` | `prim.color.danger.dark` | 删除/危险 |
| `sem.color.search.hit` | `prim.color.search` | `prim.color.search.dark` | 搜索命中描边 |
| `sem.color.edge` | `prim.color.line` | `prim.color.line.dark` | 树连线 |

### 2.4 排版语义

| token | 值 |
|-------|-----|
| `sem.font.node` | `prim.font.family.ui` / `prim.font.size.node` / weight regular |
| `sem.font.root` | `prim.font.family.ui` / `prim.font.size.root` / weight semibold |
| `sem.font.caption` | `prim.font.family.ui` / `prim.font.size.caption` / weight regular |
| `sem.font.toolbar` | `prim.font.family.ui` / `prim.font.size.toolbar` / weight medium |
| `sem.font.mono` | SF Mono（缩放/计数用 `monospacedDigit`） |

---

## 3. Component tokens（组件专用）

> 每个组件 token 引用上面语义 token，**不再出现裸值**。完整状态表见各组件规格。

### 3.1 节点（`components/node.md`）

| token | light | dark |
|-------|-------|------|
| `cmp.node.bg` | `sem.color.surface.node` | 同 |
| `cmp.node.border` | `prim.color.node.border` | 同 |
| `cmp.node.radius` | `prim.radius.node` | 同 |
| `cmp.node.shadow` | `prim.shadow.node` | 同 |
| `cmp.node.selected.border` | `sem.color.accent` | 同 |
| `cmp.node.selected.ring` | `sem.color.accent.soft` 3pt | 同 |
| `cmp.node.root.bg` | `prim.color.root.fill` | 同 |
| `cmp.node.root.radius` | `prim.radius.root` | 同 |

### 3.2 工具条（`components/toolbar.md`）

| token | light | dark |
|-------|-------|------|
| `cmp.toolbar.surface` | `sem.color.surface.toolbar` | 同 |
| `cmp.toolbar.btn.bg` | transparent | 同 |
| `cmp.toolbar.btn.hover` | `prim.color.node` @ 92% | 同 |
| `cmp.toolbar.btn.active` | `prim.color.accent.soft` | 同 |
| `cmp.toolbar.group.bg` | `prim.color.paper.1 @ 65%` | 同 |

### 3.3 分叉折叠钮（`components/canvas.md`）

| token | light | dark |
|-------|-------|------|
| `cmp.toggle.bg` | `prim.color.node` | 同 |
| `cmp.toggle.border` | `accent 55%` + `node.border` | 同 |
| `cmp.toggle.collapsed.bg` | `sem.color.accent` | 同 |
| `cmp.toggle.collapsed.text` | `sem.color.text.onAccent` | 同 |

### 3.4 编辑浮层 / 搜索条 / 横幅 / 导入预览

均锚 `sem.color.surface.overlay` + `prim.radius.card`，具体状态见各组件文件。

---

## 4. 无障碍对比度合规

| 组合 | 目标比 | 实现策略 |
|------|--------|---------|
| 正文 vs 纸面 | ≥ 4.5:1 | `ink #1A1C19` / `ink.dark #ECE9E2` 均达标 |
| 次要文字 vs 表面 | ≥ 4.5:1 | `ink.muted` 需暗色下核对；hover/disabled 时保持可读 |
| 强调上白字 / 折叠钮白字 | ≥ 4.5:1 | `accent` 底 + 白字达标；`accent.dark` 底 + 深字 `#0F1712` |
| 危险 / 搜索命中 | ≥ 3:1（非文字 UI） | 描边+图标，不靠纯色传达 |

> 全部文字走 `sem.font.*`，自动响应系统 Bold Text；颜色随 `colorScheme` + Increase Contrast 语义化（见 `swiftui-expert-skill` 无障碍检查清单）。

---

## 5. 与现状实现的对齐说明

- **填色 5 token**：`NodeFillStyle` 现有算法即本文件 `prim.color.fill.*` 的来源，**不改**。
- **PNG 导出底色**：`MetalRenderer.renderImage` 用 `paper #e7e4dc` 固定浅色 → 锚 `prim.color.paper.1.light`（`sem.color.canvas.bg.light`）。后续若做「暗色导出」另案。
- **Metal clearColor**：`MetalRenderer.swift:95` 已从 `NSColor.windowBackgroundColor` 取 → 替换为 `sem.color.canvas.bg` 的系统语义解析即可（随外观，纸感底由 `encodeContent` 画纸面渐变，见 `components/canvas.md`）。
- **布局常量**：尺寸 token 全部映射 `LayoutConstants`，改布局走 `linva-layout-snapshot` skill。

## 6. 变更记录

| 日期 | 说明 |
|------|------|
| 2026-10-02 | 首版：暖纸品牌基线，三层 token 全量定义（亮/暗），锚定现有 `NodeFillStyle` / `LayoutConstants` / `prototype styles.css` |
