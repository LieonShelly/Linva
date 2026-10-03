# YMind — Component Spec: Canvas & Edges（画布与连线）

> Metal 层。中心辐射布局：根居中，一级子 `side` 左/右。系统原生底 + 贝塞尔连线。
> 引用 token：`--s-canvas-*`、`--s-edge`。

---

## 1. 画布底

| 元素 | 规格 |
|---|---|
| 底色 | `--s-canvas-bg`（亮 `#ececec` 系统灰 / 暗 `#171719` 近黑）——现状在线 clearColor 用系统灰，补暗色动态色 |
| 深度渐变 | 无（无纸感、无渐变底） |

> **reduced-transparency**：不涉及透明材质，纯色底天然满足（HIG Rule 9.5）。

---

## 2. 连线（EdgeGeometry）

| 参数 | 规格 |
|---|---|
| 形状 | 父节点边缘 → 子节点边缘的水平贝塞尔（现状 `RadialLayout.edge` 4 点） |
| 颜色 | `--s-edge`（亮 `#c7c7cc` / 暗 `#3a3a3e`） |
| 线宽 | 1.75pt，圆头 |
| 透明度 | 0.8 |
| 生长动画 | `strokeEnd 0→1`（`motion-tokens.md §4.1`） |

**折叠隐藏的子节点连线不绘制**（现状：折叠枝无 frame/edge）。

---

## 3. 相机与工具

| 工具 | 行为 |
|---|---|
| 选择 select | 空白左拖 = 框选；点空白 = 取消选中 |
| 平移 pan | 空白左拖 = 平移；空格临时平移 |
| 缩放 | 滚轮 / 工具条 ±，锚点跟随指针，范围 0.2–4 |
| 适应画布 fit | 缩放+平移补间到内容包围盒（`--m-spring-gentle`） |

---

## 4. 框选（Marquee）

| 状态 | 视觉 | 行为 |
|---|---|---|
| 拖拽中 | accent 描边 1.5px + accent-soft 14% 填充，实时更新 | 与框相交的节点选中 |
| 完成 | 淡出 | 保留选中集 |
| ⇧ 加选 | — | `additive` 位 |

---

## 5. 无障碍

- 画布是自绘 Metal，不暴露语义；但**节点 + 分叉控件须经 SwiftUI accessibility 树暴露**（叠加 layer 提供 label），保证 VoiceOver 可达。
- 缩放/平移状态在工具条以百分比文字呈现（不只图形）。
