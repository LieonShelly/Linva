# YMind — Component Spec: NodeEditorOverlay（编辑浮层）

> SwiftUI + AppKit（`NSTextView`）浮层，覆在节点上就地编辑。现状：`NodeEditorOverlay.swift` / `CommitTextView`。
> 引用 token：`--c-edit-*`。

---

## 1. 结构

节点上覆盖一个与节点同尺寸的文本编辑框：白底（系统 `.background`）+ 系统 `.tint` 2px 环 + 圆角 10，光标定位。

---

## 2. 状态表

| 状态 | 行为 |
|---|---|
| **进入编辑** | 节点原位置原位出现，光标在文本末尾，自动聚焦 |
| **编辑中** | 白底 + tint 环；可多行（Option/⌘+Enter 换行）；⌘V 图片粘贴走壳层 |
| **提交** | Enter（无修饰）→ 提交；按 `--c-edit-ring` 淡出 |
| **取消** | Esc → 恢复原值，关闭 |
| **删空** | 见规则 3 |

---

## 3. 行为细则（删空语义，现状已定，保持）

1. Enter（无修饰）提交；Option/⌘+Enter 插入换行。
2. 有图节点删空文字 → 只留图片。
3. 非根纯文本节点删空 → **直接删除该节点**（走 `applyDelete`，Undo 可恢复）。
4. 根节点删空 → 补「未命名」。
5. 图片粘贴（⌘V 拦截 png/tiff）：先提交文字，再追加图片块到末尾（两条路径：Edit 菜单 + ⌘V 统一走 `paste(_:)`）。
6. 字号：普通节点 13pt SF Pro；根节点 15–17pt SF Pro 加粗（对齐 node.md）。

---

## 4. 无障碍

- 有 `accessibilityLabel("编辑主题")`（现状已有）。
- 文本框是真实 `NSTextView`，自动支持 VoiceOver 文本编辑。
