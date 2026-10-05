# Linva 组件规格 — 填色色点（FillSwatches）

> 层级：**SwiftUI 壳**（工具条内）。为选中节点套用/清除 5 色预设填色。规格即现有实现（`FillSwatchesView`），本文件确认视觉 token 对齐。色值引用 `design-tokens.md`。

---

## 1. 结构

| 属性 | 值 |
|------|-----|
| 位置 | 工具条 primaryAction 组（删除后） |
| 布局 | `HStack(spacing: 6)` 水平排布 |
| 成员 | 5 色点 + 默认清除点（斜线） |
| 色点尺寸 | 16pt 圆 |

---

## 2. 状态表

| 状态 | 色点 | 外环 | 动效 |
|------|------|------|------|
| 默认 | `prim.color.fill.*` | `secondary @ 35%` 1pt | — |
| hover | 同 | 同 | `scale 1.08`（`motion.duration.fast`） |
| 激活 | 同 | `sem.color.accent` 2pt + 2pt 隔环 | `motion.duration.base` |
| 默认清除 | `surface.node` + 斜线 `prim.color.danger` | 同默认 | — |
| disabled | opacity 0.35 | — | 无 |

- 激活判定：单选当前 fill；多选一致才激活；不一致无激活态。
- 无选中时全禁用。

---

## 3. 无障碍 / 合规

- 每色点 `.help("填色 <token>")` / 清除点 `.help("清除填色")`。
- 色点非纯图标：色相 + 可选文字提示双通道，不靠颜色单通道（`ui-ux-pro-max` 图标/无障碍规则）。

---

## 变更记录
| 日期 | 说明 |
|------|------|
| 2026-10-02 | 首版：色点组状态表 + token 对齐，锚定 `FillSwatchesView` / `NodeFillStyle.swatch` |
