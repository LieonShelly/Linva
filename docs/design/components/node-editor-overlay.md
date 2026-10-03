# YMind 组件规格 — 编辑浮层（NodeEditorOverlay）

> 层级：**SwiftUI 壳**（`NodeTextEditor` = `NSViewRepresentable` 包 `NSTextView`）。画布上双击/Return 进入节点文字编辑，浮层贴合节点原位。色值引用 `design-tokens.md`，动效引用 `motion-tokens.md`。

---

## 1. 结构

| 属性 | 值 |
|------|-----|
| 位置 | 贴合节点 `screenRect`（`.position(midX, midY)`） |
| 尺寸 | `max(rect, 80×36)` |
| 卡面 | `sem.color.surface.node`（`.background`) |
| 圆角 | `prim.radius.input` (8pt) |
| 描边 | `.tint` 2pt（`sem.color.accent`） |
| 文字 | `sem.font.node`；中心主题 `sem.font.root`（semibold） |
| 光标 | 文末（现状 `setSelectedRange`） |

---

## 2. 行为状态

| 触发 | 行为 |
|------|------|
| 出现 | 从节点原位 `scale 0.92→1` 淡入，`makeFirstResponder`，光标文末 |
| 提交 | Enter（无修饰键）；⌘/⌥+Enter 插换行 |
| 取消 | Esc → 复原 `originalBlocks` |
| 粘贴图片 | 拦截 png/tiff → 先提交文字再追加图片块；纯文本走 `super.paste` |
| 删空 | 非根纯文本 → 删节点；有图 → 只留图；根 → 补「未命名」（现状规则） |

---

## 3. 动效

| 事件 | token |
|------|-------|
| 入场/出场 | `motion.duration.medium` + `motion.spring.soft` |
| caret | 系统 `NSTextView` 自带 |

---

## 4. 无障碍 / 合规

- `.accessibilityLabel("编辑主题")`。
- 全键盘：Enter 提交、Esc 取消（`CommitTextView.keyDown` 现状已有）。
- 支持系统 Undo（`allowsUndo = true`）。

---

## 变更记录
| 日期 | 说明 |
|------|------|
| 2026-10-02 | 首版：贴合节点浮层 + 行为状态 + 动效，锚定 `NodeEditorOverlay` / `NodeTextEditor` / `CommitTextView` |
