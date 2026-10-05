# Linva 组件规格 — 搜索条（SearchBar）

> 层级：**SwiftUI 壳**。⌘F 打开，搜索树节点并逐跳高亮。色值引用 `design-tokens.md`，动效引用 `motion-tokens.md`。

---

## 1. 结构

| 属性 | 值 |
|------|-----|
| 位置 | 画布顶部居中浮层（工具条下方） |
| 卡面 | `sem.color.surface.overlay` + `prim.radius.card` (10pt) |
| 内容 | 放大镜 + 文本域 + 计数 + 上/下跳 + 关闭 |

---

## 2. 状态表

| 状态 | 文本域 | 按钮 | 说明 |
|------|--------|------|------|
| 默认 | `prim.radius.input` 圆角底，`node.border` | 可点 | |
| 聚焦 | `sem.color.accent` 边框 + `accent.soft` 3pt | — | 出现即获焦 |
| 无匹配 | 同聚焦 | 上/下禁用 | 计数 `0 / 0` |
| 有匹配 | 同聚焦 | 可点 | 计数 `n / N`，`monospacedDigit` |

---

## 3. 行为

| 事件 | 行为 |
|------|------|
| 打开 | ⌘F；文本域获焦；当前节点保留匹配优先回落 |
| 输入 | 查询变化优先留在仍匹配节点，否则回落首个匹配 |
| Enter / ↓ | 下一跳；⇧Enter / ↑ 上一跳；Esc 关闭 |
| 跳转 | `centerCamera` 居中命中节点（`motion.duration.medium`） |
| 命中高亮 | 画布节点 `sem.color.search` 3pt 描边（Metal 层，叠于选中之上） |

---

## 4. 动效

| 事件 | token |
|------|-------|
| 出现/关闭 | `motion.duration.fast` 自顶滑入/淡入（`motion.easing.out`） |
| 计数变化 | `.animation(.snappy, value:)` 轻微过渡（可省略） |

---

## 5. 无障碍 / 合规

- 文本域有 `.accessibilityLabel`；上/下按钮有 `.help`（上一项 ⇧Enter / 下一项 Enter）。
- 全键盘：Enter/Esc/方向键导航。

---

## 变更记录
| 日期 | 说明 |
|------|------|
| 2026-10-02 | 首版：顶部浮层搜索条 + 状态/行为/动效，锚定 `SearchBar` |
