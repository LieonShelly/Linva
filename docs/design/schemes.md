# YMind — 配色方案选型（调研 + 对比）

> 本文档记录 2026-10 的 UI 配色方向调研与四套候选方案。交互对比原型见
> [`prototype/design/schemes.html`](../../prototype/design/schemes.html)（含亮/暗切换、右侧关键色与亮点说明）。
>
> ✅ **已定案（2026-10-03）**：亮色 = **A · 系统原生**，暗色 = **D · 深色沉浸**。
> 对应 token 已回写 `design-tokens.md`，组件规格已同步（`components/*.md`）。

## 背景：为什么旧设计"不像原生"

视觉核对 `design-light.png / design-dark.png`（旧原型渲染图）确认问题点：

| 元素 | 旧设计（被否） | 原生 macOS 约定 |
|---|---|---|
| 标题栏 | 自定义一体化 + 文档名左置标签 | 标准红绿灯 + 统一工具栏 |
| 字体 | 品牌名/根节点用衬线（New York） | 全 SF Pro 无衬线 |
| 画布 | 暖纸米色 `#e7e4dc` + 点阵网格 | 系统灰 / 近白，无装饰纹理 |
| 按钮 | 网页式胶囊浮钮、键帽内嵌 | 标准工具栏按钮（图标 + 文字 Label） |
| 整体观感 | Notion / Heptabase 纸感白板 | Finder / 备忘录 / MindNode |

而当前代码（用户认可的部分）恰是：画布 `NSColor.windowBackgroundColor`（系统灰）、标准 SwiftUI 工具栏、
SF 无衬线、系统 accent —— 与 HIG 一致。

## 竞品调研结论（成熟脑图 App 的共性）

- **MindNode**（macOS 原生标杆）：近白画布 + 白卡轻阴影 + 深中性根节点 + 系统蓝 accent；
  Dynamic Themes 亮暗自动切换；节点形状可选（Rounded/Pill/…）。默认风 = 冷调素雅。
- **XMind**：设计原则 "Light and Airy / 少即是多 / 留白"；ZEN 模式去干扰；
  2025 起受 Liquid Glass + Material Design 3 启发刷新视觉；支持深色沉浸。
- **Apple Freeform（无边记）**：原生画布 App，系统材质 + 无品牌色，克制度最高。
- **共同点**：原生 chrome（红绿灯 + 标准工具栏）、干净画布、克制色系、
  亮暗双态自适应；差异集中在画布底色 / 节点填色 / accent 三者。

## 四套候选方案

> 四套**共用同一原生外壳**（红绿灯 + 标准工具栏 + SF Pro，无纸感点阵、无衬线），
> 只换色系。每套均有亮/暗双态，色值即最终 token 雏形。

### A · 系统原生（System）
- 画布 `#ececec`（= `windowBackgroundColor`）／暗 `#1e1e1e`
- 节点：系统白 `#ffffff` / 深灰 `#2c2c2e` + `separator` 细描边
- 根节点：深中性 `#3a3a3c`，白字
- accent：系统蓝 `#0a84ff`（亮）/ `#0a84ff`（暗）
- 连线 `#c7c7cc`
- 定位：**与现有代码最接近，改动最小**；"系统设置 / 备忘录"同款质感

### B · 冷调素雅（Cool，MindNode 默认风）
- 画布 `#f5f5f7` ／暗 `#1c1c1e`
- 节点：白卡 + 轻阴影 + 细描边；根节点深中性 `#1d1d1f`（暗色反转浅底深字）
- accent `#0071e3`（亮）/ `#0a84ff`（暗）
- 定位：**"高级感"标准档**，留白大、长时间看图不累

### C · 暖调中性（Warm Neutral）
- 画布 `#f6f5f1`（极浅暖白）／暗 `#20201d`
- 根节点：深暖灰 `#2f2c26`；accent 琥珀 `#8a5b2e`（暗 `#c98d55`）
- 定位：**保留温度但不纸感**，与"暖纸"划清界限；accent 有辨识度

### D · 深色沉浸（Dark Immersive）
- 画布 `#171719` 近黑 ／亮 `#e8e8ea`
- 根节点用 accent 蓝 `#0a84ff` 点亮，层级清楚
- 定位：**暗色优先**，护眼沉浸，类似 XMind / 系统级深色工具

## 落地约束（无论选哪套）

- 画布色：`MetalRenderer` 在线 `clearColor` 改用动态 `NSColor`（亮暗随外观解析），替换现有 `windowBackgroundColor` 固定灰
- 根节点字体：去掉 New York 衬线，回 SF Pro；根节点加粗即可（`LayoutSnapshot` / 文字纹理侧）
- 边框/圆角：节点 8pt、根节点 10pt（对齐系统控件半径阶梯），去掉原型 14/18pt 大圆角
- 填色 5 token（sage/sky/sand/rose/lilac）：保留为"分类工具"，饱和度随方案档位调整
- 分叉控件：展开态白底灰边 + 折叠态 accent 实心（现状已符合，仅对齐色值）
- 无点阵网格；无自定义标题栏

## 决策（已定）

- [x] **亮色 = A · 系统原生；暗色 = D · 深色沉浸**（A 主 + D 深色）
- [x] 填色 5 色（sage/sky/sand/rose/lilac）保留为分类工具；亮色可整体降饱和 10–15% 再定档
- [x] 全 SF Pro 无衬线；节点圆角 8 / 根节点 10；无纸感、无点阵、无自定义标题栏
