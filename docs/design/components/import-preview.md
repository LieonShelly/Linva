# YMind 组件规格 — 导入预览（ImportPreviewView）

> 层级：**SwiftUI 壳**。导入 MD/OPML/FreeMind 解析成功后，先展示解析出的树（缩进列表）确认/取消，再载入。色值引用 `design-tokens.md`。

---

## 1. 结构

| 属性 | 值 |
|------|-----|
| 位置 | 画布顶部居中浮层 |
| 卡面 | `sem.color.surface.overlay` + `prim.radius.card` (12pt) |
| 尺寸 | 固定 420pt 宽 |
| 内容 | 标题 + 元信息（源名 · N 节点 · 深度）+ 缩进树滚动区 + 取消/确认 |

---

## 2. 状态表

| 元素 | 默认 | hover | active |
|------|------|-------|--------|
| 标题 | `font.headline` | — | — |
| 元信息 | `subheadline` + `text.secondary` | — | — |
| 缩进树 | 递归 `◎ / –` 前缀，层缩进 2 字符 | — | — |
| 取消 | 默认按钮 | — | — |
| 确认导入 | `borderedProminent`（`sem.color.accent`） | — | — |

---

## 3. 行为

| 事件 | 行为 |
|------|------|
| 打开 | 解析成功后展示（不改磁盘既有 `.ymind`） |
| 确认 | `loadImported` → 清命令栈、重置 documentID、标记 dirty、树入场 |
| 取消 / Esc | `cancelImport`，保持当前文档 |
| 导入失败 | 清旧预览 + 顶部错误横幅（`sem.color.danger`） |

---

## 4. 无障碍 / 合规

- 树形缩进列表可读（非纯视觉：前缀字符区分层级）。
- 确认/取消可键盘：Enter 确认、Esc 取消。

---

## 变更记录
| 日期 | 说明 |
|------|------|
| 2026-10-02 | 首版：导入预览浮层 + 状态/行为，锚定 `ImportPreviewView` / `DocumentWorkflow.presentImportPanel` |
